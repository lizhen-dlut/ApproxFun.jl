



##interlace block operators
function isboundaryrow(A,k)
    for j=1:size(A,2)
        if isafunctional(A[k,j])
            return true
        end
    end

    return false
end



domainscompatible{T<:Operator}(A::Matrix{T})=domainscompatible(map(domainspace,A))

function spacescompatible{T<:Operator}(A::Matrix{T})
    for k=1:size(A,1)
        if !spacescompatible(map(rangespace,vec(A[k,:])))
            return false
        end
    end
    for k=1:size(A,2)
        if !spacescompatible(map(domainspace,A[:,k]))
            return false
        end
    end
    true
end

spacescompatible{T<:Operator}(A::Vector{T}) = spacescompatible(map(domainspace,A))

function domainspace{T<:Operator}(A::Matrix{T})
    @assert spacescompatible(A)

    spl=map(domainspace,vec(A[1,:]))
    if spacescompatible(spl)
        ArraySpace(first(spl),length(spl))
    elseif domainscompatible(spl)
        TupleSpace(spl)
    else
        PiecewiseSpace(spl)
    end
end

function rangespace{T<:Operator}(A::Vector{T})
    @assert spacescompatible(A)

    spl=map(rangespace,A)
    if spacescompatible(spl)
        ArraySpace(first(spl),length(spl))
    else
        TupleSpace(spl)
    end
end

function promotespaces{T<:Operator}(A::Matrix{T})
    isempty(A) && return A
    A=copy(A)#TODO: promote might have different Array type
    for j=1:size(A,2)
        A[:,j]=promotedomainspace(A[:,j])
    end
    for k=1:size(A,1)
        A[k,:]=promoterangespace(vec(A[k,:]))
    end

    # do a second loop as spaces might have been inferred
    # during range space
    for j=1:size(A,2)
        A[:,j]=promotedomainspace(A[:,j])
    end
    A
end


## Interlace operator

immutable InterlaceOperator{T,p,DS,RS,DI,RI,BI} <: Operator{T}
    ops::Array{Operator{T},p}
    domainspace::DS
    rangespace::RS
    domaininterlacer::DI
    rangeinterlacer::RI
    bandinds::BI
end


InterlaceOperator{T,p}(ops::Array{T,p},ds,rs,di,ri,bi) =
    InterlaceOperator{T,p,typeof(ds),typeof(rs),
                        typeof(di),typeof(ri),typeof(bi)}(ops,ds,rs,di,ri,bi)

function InterlaceOperator{T}(ops::Matrix{Operator{T}},ds::Space,rs::Space)
    # calculate bandinds TODO: generalize
    p=size(ops,1)
    if size(ops,2) == p && all(isbanded,ops)
        l,u = 0,0
        for k=1:p,j=1:p
            l=min(l,p*bandinds(ops[k,j],1)+j-k)
        end
        for k=1:p,j=1:p
            u=max(u,p*bandinds(ops[k,j],2)+j-k)
        end
    elseif p == 1 && size(ops,2) == 2 && size(ops[1],2) == 1
        # special case for example
        l,u = min(bandinds(ops[1],1),bandinds(ops[2],1)+1),bandinds(ops[2],2)+1
    else
        l,u = (1-dimension(rs),dimension(ds)-1)  # not banded
    end


    InterlaceOperator(ops,ds,rs,
                        cache(interlacer(ds)),
                        cache(interlacer(rs)),
                        (l,u))
end


function InterlaceOperator{T}(ops::Vector{Operator{T}},ds::Space,rs::Space)
    # calculate bandinds
    p=size(ops,1)
    if all(isbanded,ops)
        l,u = 0,0
        for k=1:p
            l=min(l,p*bandinds(ops[k],1)+1-k)
        end
        for k=1:p
            u=max(u,p*bandinds(ops[k],2)+1-k)
        end
    else
        l,u = (1-dimension(rs),dimension(ds)-1)  # not banded
    end


    InterlaceOperator(ops,ds,rs,
                        InterlaceIterator(tuple(dimension(ds))),
                        cache(interlacer(rs)),
                        (l,u))
end

function InterlaceOperator{T}(opsin::Matrix{Operator{T}})
    isempty(opsin) && throw(ArgumentError("Cannot create InterlaceOperator from empty Matrix"))

    ops=promotespaces(opsin)
    # TODO: make consistent
    # if its a row vector, we assume scalar
    if size(ops,1) == 1
        InterlaceOperator(ops,domainspace(ops),rangespace(ops[1]))
    else
        InterlaceOperator(ops,domainspace(ops),rangespace(ops[:,1]))
    end
end

function InterlaceOperator{T}(opsin::Vector{Operator{T}})
    ops=promotedomainspace(opsin)
    InterlaceOperator(ops,domainspace(first(ops)),rangespace(ops))
end

InterlaceOperator{T,p}(ops::Array{T,p}) =
    InterlaceOperator(Array{Operator{mapreduce(eltype,promote_type,ops)},p}(ops))


function Base.convert{T}(::Type{Operator{T}},S::InterlaceOperator)
    if T == eltype(S)
        S
    else
        ops=Array(Operator{T},size(S.ops)...)
        for j=1:size(S.ops,2),k=1:size(S.ops,1)
            ops[k,j]=S.ops[k,j]
        end
        InterlaceOperator(ops,domainspace(S),rangespace(S),
                            S.domaininterlacer,S.rangeinterlacer,S.bandinds)
    end
end



#TODO: More efficient to save bandinds
bandinds(M::InterlaceOperator) = M.bandinds

function getindex{T}(op::InterlaceOperator{T,2},k::Integer,j::Integer)
    M,J = op.domaininterlacer[j]
    N,K = op.rangeinterlacer[k]
    op.ops[N,M][K,J]::T
end

# the domain is not interlaced
function getindex{T}(op::InterlaceOperator{T,1},k::Integer,j::Integer)
    N,K = op.rangeinterlacer[k]
    op.ops[N][K,j]::T
end

function getindex{T}(op::InterlaceOperator{T},k::Integer)
    if size(op,1) == 1
        op[1,k]
    elseif size(op,2) == 1
        op[k,1]
    else
        error("Only implemented for row/column operators.")
    end
end

#####
# optimized copy routine for when there is a single domainspace
# and no interlacing of the columns is necessary
# this is especially important for \
######

function Base.convert{SS,PS,DI,RI,BI,T}(::Type{Matrix},
                            S::SubOperator{T,InterlaceOperator{T,1,SS,PS,DI,RI,BI}})
    kr,jr=parentindexes(S)
    P=parent(S)
    ret=Array(eltype(S),size(S,1),size(S,2))
    for k in eachindex(kr)
        K,κ=P.rangeinterlacer[kr[k]]
        @inbounds ret[k,:]=P.ops[K][κ,jr]
    end
    ret
end

function Base.convert{SS,PS,DI,RI,BI,T}(::Type{BandedMatrix},
                            S::SubOperator{T,InterlaceOperator{T,1,SS,PS,DI,RI,BI}})
    kr,jr=parentindexes(S)
    P=parent(S)
    ret=BandedMatrix(eltype(S),size(S,1),size(S,2),bandwidth(S,1),bandwidth(S,2))
    for j=1:size(ret,2),k=colrange(ret,j)
        K,κ=P.rangeinterlacer[kr[k]]
        @inbounds ret[k,j]=P.ops[K][κ,jr[j]]
    end
    ret
end


domainspace(IO::InterlaceOperator) = IO.domainspace
rangespace(IO::InterlaceOperator) = IO.rangespace

#tests whether an operator can be made into a column
iscolop(op) = isconstop(op)
iscolop(::Multiplication) = true

promotedomainspace{T}(A::InterlaceOperator{T,1},sp::Space) =
    InterlaceOperator(map(op->promotedomainspace(op,sp),A.ops))

choosedomainspace{T}(A::InterlaceOperator{T,1},sp::Space) =
    filter(x->!isambiguous(x),map(s->choosedomainspace(s,sp),A.ops))[1]


interlace{T<:Operator}(A::Array{T}) = length(A)==1?A[1]:InterlaceOperator(A)

immutable DiagonalInterlaceOperator{OPS,DS,RS,T<:Number} <: Operator{T}
    ops::OPS
    domainspace::DS
    rangespace::RS
end

function DiagonalInterlaceOperator(v::Tuple,ds::Space,rs::Space)
    T=mapreduce(eltype,promote_type,v)
    w=map(Operator{T},v)
    DiagonalInterlaceOperator{typeof(w),typeof(ds),typeof(rs),T}(w,ds,rs)
end
DiagonalInterlaceOperator{ST<:Space}(v::Tuple,::Type{ST})=DiagonalInterlaceOperator(v,ST(map(domainspace,v)),ST(map(rangespace,v)))
DiagonalInterlaceOperator(v::Vector,k...)=DiagonalInterlaceOperator(tuple(v...),k...)


Base.convert{T}(::Type{Operator{T}},op::DiagonalInterlaceOperator)=
        DiagonalInterlaceOperator(map(Operator{T},op.ops),op.domainspace,op.rangespace)


function bandinds(S::DiagonalInterlaceOperator)
    binds=map(bandinds,S.ops)
    bra=mapreduce(first,min,binds)
    brb=mapreduce(last,max,binds)
    n=length(S.ops)
    n*bra,n*brb
end


function getindex(D::DiagonalInterlaceOperator,k::Integer,j::Integer)
    n=length(D.ops)
    mk = n+mod(k,-n)
    T=eltype(D)
    if mk == n+mod(j,-n)  # same block
        k=(k-1)÷n+1  # map k and j to block coordinates
        j=(j-1)÷n+1
        D.ops[mk][k,j]::T
    else
        zero(T)
    end
end

domainspace(D::DiagonalInterlaceOperator)=D.domainspace
rangespace(D::DiagonalInterlaceOperator)=D.rangespace



## Convert Matrix operator to operators

Base.convert{OO<:Operator}(::Type{Operator},M::Array{OO}) = InterlaceOperator(M)
