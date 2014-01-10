export ToeplitzOperator, HankelOperator, MultiplicationOperator






type ToeplitzOperator{V<:Union(Vector,ShiftVector)} <: BandedOperator
    coefficients::V
end

ToeplitzOperator(f::AbstractFun)=ToeplitzOperator(f.coefficients)




function addentries!{M<:Vector}(T::ToeplitzOperator{M},A::ShiftArray,kr::Range1)
    v = T.coefficients
    
    
    for k=kr,j=1-length(v):length(v)-1
        A[k,j] += (j ==0) ? 2v[1] : v[abs(j)+1]
    end
    
    A
end


bandrange{M<:Vector}(T::ToeplitzOperator{M})=(1-length(T.coefficients):length(T.coefficients)-1)



function addentries!{M<:ShiftVector}(T::ToeplitzOperator{M},A::ShiftArray,kr::Range1)
    v = T.coefficients
    
    
    for k=kr,j=range(v)[1]:range(v)[end]
        A[k,j] += v[j]
    end
    
    A
end


bandrange{M<:ShiftVector}(T::ToeplitzOperator{M})=range(T.coefficients)


## Hankel Operator


type HankelOperator <: BandedOperator
    coefficients::Vector
end

HankelOperator(f::IFun)=HankelOperator(f.coefficients)

function addentries!(T::HankelOperator,A::ShiftArray,kr::Range1)
    v=T.coefficients
  
    for j=1:length(v)
        for k=intersect(kr,1:j)
            A[k,j-2k+1] += v[j]
        end
    end
    
    A
end


bandrange(T::HankelOperator)=(1-length(T.coefficients):length(T.coefficients)-1)


## MultiplicationOperator

type MultiplicationOperator <: BandedOperator
    T::ToeplitzOperator
    H::HankelOperator
end

MultiplicationOperator(f::IFun)=MultiplicationOperator(ToeplitzOperator(.5f),HankelOperator(.5f))


function addentries!(M::MultiplicationOperator,A::ShiftArray,kr::Range1)
    addentries!(M.T,A,kr)
    addentries!(M.H,A,kr)        
    
    if kr[1] == 1  
        for j=1:length(M.H.coefficients)
            A[1,j-1] -= M.H.coefficients[j]
        end
    end   
    
    A
end


bandrange(T::MultiplicationOperator)=(1-length(T.T.coefficients):length(T.T.coefficients)-1)




