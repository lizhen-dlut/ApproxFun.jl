## VectorSpace{T,S} encodes a space that is a Vector, with coefficients interlaced


immutable VectorDomainSpace{S,T} <: DomainSpace{T}
     space::S
     length::Int
 end

VectorDomainSpace{T}(S::DomainSpace{T},n)=VectorDomainSpace{typeof(S),T}(S,n)
Base.length(S::VectorDomainSpace)=S.length

domain(S::VectorDomainSpace)=domain(S.space)
transform(S::VectorDomainSpace,vals::Vector)=transform!(S,hcat(vals...).')


function transform!(S::VectorDomainSpace,M::Array)
    @assert size(M,2)==S.length
    for k=1:size(M,2)
        M[:,k]=transform(S.space,M[:,k])
    end
    vec(M.')
end

Base.vec{S<:DomainSpace,V,T}(f::Fun{VectorDomainSpace{S,V},T})=Fun{S,T}[Fun(f.coefficients[j:length(f.space):end],f.space.space) for j=1:length(f.space)]

evaluate{V<:VectorDomainSpace,T}(f::Fun{V,T},x)=evaluate(vec(f),x)

for op in (:differentiate,:integrate,:(Base.cumsum))
    @eval $op{V<:VectorDomainSpace}(f::Fun{V})=devec(map($op,vec(f)))
end




## Separate domains

immutable UnionDomain{D<:Domain} <:Domain
    domains::Vector{D}
end

∪(d1::UnionDomain,d2::UnionDomain)=UnionDomain([d1.domains,d2.domains])
∪(d1::Domain,d2::UnionDomain)=UnionDomain([d1,d2.domains])
∪(d1::UnionDomain,d2::Domain)=UnionDomain([d1.domains,d2])
∪(d1::Domain,d2::Domain)=UnionDomain([d1,d2])
Base.length(d::UnionDomain)=d.domains|>length
Base.getindex(d::UnionDomain,k)=d.domains[k]
for op in (:(Base.first),:(Base.last))
    @eval $op(d::UnionDomain)=d.domains|>$op|>$op
end

function points(d::UnionDomain,n)
   k=div(n,length(d))
    r=n-length(d)*k

    [vcat([points(d.domains[j],k+1) for j=1:r]...),
        vcat([points(d.domains[j],k) for j=r+1:length(d)]...)]
end



immutable DirectSumSpace{S<:FunctionSpace,T} <: DomainSpace{T}
    spaces::Vector{S} 
end

DirectSumSpace{S,T}(::DomainSpace{T},spaces::Vector{S})=DirectSumSpace{S,T}(spaces)
DirectSumSpace(spaces)=DirectSumSpace(first(spaces),spaces)
Space(d::UnionDomain)=DirectSumSpace(map(Space,d.domains))
domain(S::DirectSumSpace)=UnionDomain(map(domain,S.spaces))
Base.length(S::DirectSumSpace)=S.spaces|>length

Base.vec{S<:DomainSpace,V,T}(f::Fun{DirectSumSpace{S,V},T})=Fun{S,T}[Fun(f.coefficients[j:length(f.space):end],f.space.spaces[j]) for j=1:length(f.space)]

function transform{T}(S::DirectSumSpace,vals::Vector{T})
    n=length(vals)
    K=length(S)
   k=div(n,K)
    r=n-K*k
    M=Array(Float64,k+1,K)
    
    for j=1:r
        M[:,j]=transform(S.spaces[j],vals[(j-1)*(k+1)+1:j*(k+1)])
    end
    for j=r+1:length(S)
        M[1:k,j]=transform(S.spaces[j],vals[r*(k+1)+(j-r-1)*k+1:r*(k+1)+(j-r)*k]) 
        M[k+1,j]=zero(T)
    end    
    vec(M.')
end

itransform(S::DirectSumSpace,cfs::Vector)=vcat([itransform(S.spaces[j],cfs[j:length(f.space):end]) for j=1:length(S)]...)


function evaluate{S<:DirectSumSpace}(f::Fun{S},x::Number)
    d=domain(f)
    vf=vec(f)
    for k=1:length(d)
        if in(x,d[k])
            return vf[k][x]
        end 
    end
end



## devec, asssume if domains the same we are vector




function devec{S,T}(v::Vector{Fun{S,T}})
    if mapreduce(space,isequal,v)
        Fun(vec(coefficients(v).'),VectorDomainSpace(space(first(v)),length(v)))
    else
        Fun(vec(coefficients(v).'),DirectSumSpace(map(space,v)))
    end
end


