
struct FineToCoarseIndices <: AbstractVector{Tuple{Vector{Int32},Vector{Int32}}}
  fcell_to_cids :: Vector{Vector{Int32}}
  cid_to_fcells :: Vector{Vector{Int32}}
  cid_to_fids   :: Vector{Vector{Int32}}
  one_to_one    :: Bool
  function FineToCoarseIndices(
    fcell_to_cids::AbstractVector{<:AbstractVector{<:Integer}}
  )
    fcell_to_cids = collect(Vector{Int32},fcell_to_cids)

    n_cids = maximum(map(maximum,fcell_to_cids))
    cid_to_fcells = [Int32[] for i in 1:n_cids]
    cid_to_fids = [Int32[] for i in 1:n_cids]
    for (fcell,cids) in enumerate(fcell_to_cids)
      for (fid,cid) in enumerate(cids)
        push!(cid_to_fcells[cid],fcell)
        push!(cid_to_fids[cid],fid)
      end
    end
    one_to_one = all(fids -> isone(length(fids)),cid_to_fids)
    new(fcell_to_cids,cid_to_fcells,cid_to_fids,one_to_one)
  end
end

Base.size(a::FineToCoarseIndices) = (length(a.cid_to_fids),)
function Base.getindex(a::FineToCoarseIndices,cid::Integer)
  (a.cid_to_fcells[cid],a.cid_to_fids[cid])
end

struct FineToCoarseArray{T,R} <: AbstractVector{T}
  rrule :: RefinementRule
  coarse_data :: Vector{T}
  fine_data   :: Vector{R}
  ids :: FineToCoarseIndices
end

function FineToCoarseArray(
  rrule::RefinementRule,
  fine_data::Vector{<:AbstractVector},
  ids :: FineToCoarseIndices
)
  coarse_data = map(ids) do (fcells,fids)
    fdata = map((fcell,fid) -> getindex(fine_data[fcell],Int(fid)),fcells,fids)
    combine_fine_to_coarse(rrule,fdata,fcells)
  end
  return FineToCoarseArray(rrule,coarse_data,fine_data,ids)
end

function FineToCoarseArray(
  rrule::RefinementRule,
  fine_data::Vector{<:AbstractVector},
  connectivity::AbstractVector{<:AbstractVector{<:Integer}}
)
  ids = FineToCoarseIndices(connectivity)
  return FineToCoarseArray(rrule,fine_data,ids)
end

function FineToCoarseArray(
  rrule::RefinementRule,
  fine_data::Vector{<:AbstractVector}
)
  offsets = cumsum(map(length,fine_data)) .- length(first(fine_data)) .+ 1
  connectivity = map(fine_data,offsets) do fdata,o
    collect(Int32,o:o+length(fdata)-1)
  end
  return FineToCoarseArray(rrule,fine_data,connectivity)
end

Base.size(a::FineToCoarseArray) = size(a.coarse_data)
Base.getindex(a::FineToCoarseArray,i::Integer) = getindex!(array_cache(a),a,i)
Arrays.array_cache(a::FineToCoarseArray) = nothing
Arrays.getindex!(cache,a::FineToCoarseArray,i::Integer) = getindex(a.coarse_data,i)

function combine_fine_to_coarse(
  rr::RefinementRule,fine_fields::Vector{<:Field},child_ids::Vector{<:Integer}
)
  FineToCoarseField(fine_fields,rr,child_ids)
end

struct FineToCoarseDof <: Dof end
function combine_fine_to_coarse(
  rr::RefinementRule,fine_dofs::Vector{<:Dof},child_ids::Vector{<:Integer}
)
  FineToCoarseDof() # Should we define this? 
end

function combine_fine_to_coarse(
  rr::RefinementRule,fine_pts::Vector{<:Point},child_ids::Vector{<:Integer}
)
  cmaps = get_cell_map(rr)
  evaluate(cmaps[first(child_ids)],first(fine_pts))
end

function Arrays.return_cache(a::FineToCoarseArray,b::FineToCoarseArray)
  @check a.rrule == b.rrule
  caches = map(return_cache,a.fine_data,b.fine_data)
  
  T = eltype(evaluate!(first(caches),first(a.fine_data),first(b.fine_data)))
  res = zeros(T,length(a),length(b))
  return res, caches
end

function Arrays.evaluate!(cache,a::FineToCoarseArray,b::FineToCoarseArray)
  res, caches = cache
  fill!(res,zero(eltype(res)))
  cell_vals = map(evaluate!,caches,a.fine_data,b.fine_data)
  for fcell in 1:num_subcells(a.rrule)
    I = a.ids.fcell_to_cids[fcell]
    J = b.ids.fcell_to_cids[fcell]
    res[I,J] .= cell_vals[fcell]
  end
  return res
end

const MacroFEBasis = FineToCoarseArray{<:Field}
const MacroDofBasis = FineToCoarseArray{<:Dof}
const MacroPoints = FineToCoarseArray{<:Point}

# Extra stuff for interpolation of arbitrary fields

function Arrays.return_cache(dofs::MacroDofBasis,f::Field)
  cmap = get_cell_map(dofs.rrule)
  caches = map((dofs_k,mk) -> return_cache(dofs_k,f∘mk),dofs.fine_data,cmap)
  T = eltype(evaluate!(first(caches),first(dofs.fine_data),f∘first(cmap)))
  res = zeros(T,length(dofs))

  return res, cmap, caches
end

function Arrays.evaluate!(cache,dofs::MacroDofBasis,f::Field)
  res, cmap, caches = cache
  fill!(res,zero(eltype(res)))
  cell_vals = map((cache_k,dofs_k,mk) -> evaluate!(cache_k,dofs_k,f∘mk),caches,dofs.fine_data,cmap)
  for fcell in 1:num_subcells(dofs.rrule)
    dof_ids = dofs.ids.fcell_to_cids[fcell]
    res[dof_ids] .= cell_vals[fcell]
  end
  return res
end

# Optimisations for MacroFEBasis


############################################################################################
# MacroReferenceFE

struct MacroRefFE <: ReferenceFEName end

function MacroReferenceFE(
  rrule::RefinementRule,
  reffes::AbstractVector{<:ReferenceFE},
)
  @check length(reffes) == num_subcells(rrule)

  grid = rrule.ref_grid
  space = FESpace(grid,reffes)

  conn = get_cell_dof_ids(space)
  basis = FineToCoarseArray(rrule,collect(map(get_shapefuns,reffes)),conn)
  dofs  = FineToCoarseArray(rrule,collect(map(get_dof_basis,reffes)),conn)
  face_dofs = get_macro_face_own_dofs(rrule,space,reffes)

  ndofs = num_free_dofs(space)
  poly = get_polytope(rrule)
  prebasis = FineToCoarseArray(rrule,collect(map(get_prebasis,reffes)))
  conformity = Conformity(first(reffes))
  @check all(r -> Conformity(r) == conformity,reffes)
  metadata = (rrule,conn)

  return GenericRefFE{MacroRefFE}(
    ndofs,poly,prebasis,dofs,conformity,metadata,face_dofs,basis
  )
end

ReferenceFEs.get_order(reffe::GenericRefFE{MacroRefFE}) = maximum(get_orders(reffe))

function ReferenceFEs.get_orders(reffe::GenericRefFE{MacroRefFE})
  prebasis = get_prebasis(reffe)
  subcell_prebasis = prebasis.fine_data
  subcell_orders = map(get_orders,subcell_prebasis)
  return map(maximum,subcell_orders)
end

function ReferenceFEs.get_face_own_dofs(reffe::GenericRefFE{MacroRefFE}, conf::Conformity)
  @check conf == Conformity(reffe)
  return get_face_dofs(reffe)
end

function get_macro_face_own_dofs(
  rrule::RefinementRule{<:Polytope{Dc}},
  space::FESpace,
  reffes::AbstractVector{<:ReferenceFE}
) where Dc
  ncells = num_subcells(rrule)
  nfaces = sum(d -> num_faces(get_polytope(rrule),d),0:Dc)
  parent_offsets = get_offsets(get_polytope(rrule))
  d_to_face_to_parent_face, d_to_face_to_parent_face_dim = Adaptivity.get_d_to_face_to_parent_face(rrule)

  grid = rrule.ref_grid
  topo = get_grid_topology(grid)
  d_to_cell_to_dface = map(Df -> Geometry.get_faces(topo,Dc,Df),0:Dc)

  cell_to_dofs = get_cell_dof_ids(space)
  cell_to_lface_to_dof = lazy_map(get_face_own_dofs,reffes)
  cell_to_offsets = lazy_map(r -> get_offsets(get_polytope(r)),reffes)

  face_to_dof = [Int[] for i in 1:nfaces]
  touched = fill(false,num_free_dofs(space))

  for cell in 1:ncells
    dofs = view(cell_to_dofs,cell)
    lface_to_dof = cell_to_lface_to_dof[cell]
    offsets = cell_to_offsets[cell]
    for d in 0:Dc
      o = offsets[d+1]
      face_to_parent_face = d_to_face_to_parent_face[d+1]
      face_to_parent_dim = d_to_face_to_parent_face_dim[d+1]
      for (lface,face) in enumerate(d_to_cell_to_dface[d+1][cell])
        face_dofs = view(dofs,lface_to_dof[o+lface])
        parent_face = face_to_parent_face[face]
        parent_dim = face_to_parent_dim[face]
        pos = parent_offsets[parent_dim+1] + parent_face
        for dof in face_dofs
          if !touched[dof]
            push!(face_to_dof[pos],dof)
            touched[dof] = true
          else
            @check dof ∈ face_to_dof[pos]
          end
        end
      end
    end
  end
  @check all(touched)

  return face_to_dof
end

############################################################################################

# MacroFESpace

# For dispatching:
#    - CellData in trian can be mapped to subcells using the glue (change domain)
#    - Dispatches to create macro-cell measures
#    - Dispatches on FESpace to create a FESpace with a macro basis
#struct MacroTriangulation
#  trian::Triangulation
#  glue::AdaptivityGlue
#end
