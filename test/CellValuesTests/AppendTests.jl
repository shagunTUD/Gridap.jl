##
using Test
using LinearAlgebra: inv, det

using Numa
using Numa.FieldValues
using Numa.CellValues


vc1_l = [1, 1, 2, 2, 1, 1, 2, 2]
vc1_p = [1, 2, 4, 5, 6, 8, 9]
vc_1 = CellVectorFromDataAndPtrs(vc1_l, vc1_p)
isa(vc_1, IndexCellValue{<:AbstractArray{Int64,1},1})
l1 = length(vc_1)
s1 = size(vc_1)

vc2_l = [1, 1, 1, 1, 2, 2, 2, 2]
vc2_p = [1, 2, 3, 4, 6, 7, 8, 9]
vc_2 = CellVectorFromDataAndPtrs(vc2_l, vc2_p)
isa(vc_2, IndexCellArray{Int64,1})
l2 = length(vc_2)
s2 = size(vc_2)
length(size(vc_2))

vc3_l = [3, 3, 4, 5, 6]
vc3_p = [1, 2, 6]
vc_3 = CellVectorFromDataAndPtrs(vc3_l, vc3_p)

@testset "IndexCellValueByGlobalAppend" begin
  using Numa.CellValues: IndexCellValueByGlobalAppend
  vc12 = IndexCellValueByGlobalAppend(vc_1,vc_2)

  @test size(vc12) == (length(vc_1)+length(vc_2),)

  for i in 1:length(vc_1)
    @test vc12[i] == vc_1[i]
  end

  for i in 1:length(vc_2)
    @test vc12[i+length(vc_1)] == vc_2[i]
  end

  vc123 = IndexCellValueByGlobalAppend(vc12, vc_3)
  nvc123 = IndexCellValueByGlobalAppend(vc_1, vc_2, vc_3)
  @test sum(vc123 .== nvc123) == length(nvc123)
  @test size(nvc123) == (length(vc12)+length(vc_3),)

  for i in 1:length(vc_1)
    @test nvc123[i] == vc_1[i]
  end

  for i in 1:length(vc_2)
    @test nvc123[i+length(vc_1)] == vc_2[i]
  end

  for i in 1:length(vc_3)
    @test nvc123[i+length(vc12)] == vc_3[i]
  end
end

cv1_1 = [1, 2, 4, 5]
cv2_1 = [2, 3, 5, 6]
_cv_1 = [cv1_1, cv2_1]
cv_1 = CellValueFromArray(_cv_1)
isa(cv_1, IndexCellValue{<:AbstractArray{Int64,1},1})
length(cv_1)

cv1_2 = [1, 2, 3, 4]
cv2_2 = [5, 6, 4, 7]
_cv_2 = [cv1_2, cv2_2]
cv_2 = CellValueFromArray(_cv_2)
isa(cv_2, IndexCellValue)
length(cv_2)