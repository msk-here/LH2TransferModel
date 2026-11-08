function model=LH2FinalPressureProblem(P,z,rhs,observe,pStop)
%LH2FINALPRESSUREPROBLEM Bind the host's unchanged physical branches.
clock=tic;observerCalls=0;fieldCalls=0;
model.surfaces=@surfaces;model.normal=@normal;model.context=@context;model.chart=@chart;model.verify=@verify;
model.fields=@fields;model.domain=@domain;model.counters=@counters;
model.validateHandoff=@(h,t,x)LH2AcceptedEvent('validate',P,z,h,t,x);
model.coordinateBudget=1e-10;model.roundoffFactor=512;
 function s=observed(t,x)
  observerCalls=observerCalls+1;guard;s=observe(t,x);
 end
 function g=surfaces(t,x)
  s=observed(t,x);g=[s.p1-P.p_ST_final;s.p2-P.p_ET_final];
 end
 function [n,u,meta]=normal(t,x,i)
  [n,u,meta]=LH2PressureChart('normal',@observed,t,x,i);
 end
 function c=context(t,x,i)
  targets=[P.p_ST_final P.p_ET_final];c=LH2PressureChart('context',@observed,t,x,i,targets(i));
 end
 function [x,d]=chart(t,x,c)
  [x,d]=LH2PressureChart('root',@observed,t,x,c);
 end
 function d=verify(t,x,c,F,n)
  d=LH2PressureChart('verify',@observed,t,x,c,F,n);
 end
 function [f,flux]=fields(t,x,bits)
  fieldCalls=fieldCalls+1;guard;mode=z;mode.finalVentBinary=bits(:)';[f,~,flux]=rhs(t,x,mode);
  if any(~isfinite(f))||~isreal(f),error('LH2:MethodRNonfinite','Nonfinite physical branch');end
 end
 function v=domain(t,x)
  if isfinite(pStop),s=observed(t,x);v=s.p2-pStop;else,v=-1;end
 end
 function c=counters
  c=struct('observerCalls',observerCalls,'fieldCalls',fieldCalls,'wallSeconds',toc(clock));
 end
 function guard
  if observerCalls>20000||fieldCalls>5000||toc(clock)>60,error('LH2:MethodRWorkCap','Final-pressure callback work cap exhausted');end
 end
end
