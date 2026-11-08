function varargout=LH2MethodR(action,varargin)
%LH2METHODR Single-surface final-relay integration, pure trial evaluations.
switch action
 case 'initialize',[varargout{1:nargout}]=initialize(varargin{:});
 case 'classify',varargout{1}=classify(varargin{:});
 case 'field',[varargout{1:nargout}]=field(varargin{:});
 case 'run',varargout{1}=run(varargin{:});
 case 'deval',varargout{1}=dense(varargin{:});
 otherwise,error('LH2:MethodRAction','Unknown Method R action');
end
end
function q=classify(m,t,x,bits,i)
[n,u]=m.normal(t,x,i);c=bits;c(i)=0;o=bits;o(i)=1;[fc,~]=m.fields(t,x,c);[fo,~]=m.fields(t,x,o);
a=n'*fc;b=n'*fo;ua=u'*abs(fc);ub=u'*abs(fo);
q=struct('kind','','bit',bits(i),'a',a,'b',b,'uncertainty',[ua ub],'normal',n,'normalUncertainty',u);
if a>ua&&b<-ub,q.kind='sliding';
elseif a>ua&&b>ub,q.kind='crossing';q.bit=1;
elseif a<-ua&&b<-ub,q.kind='crossing';q.bit=0;
elseif a==0&&b==0&&isequaln(fc,fo),q.kind='coincident fields';
else,error('LH2:MethodRClassification','Repelling, tangent or unresolved final-pressure encounter');end
end
function [F,d]=field(m,t,x,mode,audit)
if nargin<5,audit=false;end
bits=mode.bits;d=struct('bits',bits,'weights',bits,'active',mode.active,'alpha',NaN,'a',NaN,'b',NaN,'constraintResidual',NaN,'omittedResidual',NaN,'chartDifference',0,'flux',struct,'mode',mode,'independentOmitted',struct);
if mode.active==0
 [F,d.flux]=m.fields(t,x,bits);return
end
[xc,rd]=m.chart(t,x,mode.context);i=mode.active;[n,u]=m.normal(t,xc,i);closed=bits;opened=bits;closed(i)=0;opened(i)=1;
[fc,lc]=m.fields(t,xc,closed);[fo,lo]=m.fields(t,xc,opened);a=n'*fc;b=n'*fo;unc=u'*(abs(fc)+abs(fo));
if abs(a-b)<=unc,error('LH2:MethodRConditioning','Sliding normal leverage unresolved');end
alpha=a/(a-b);F=(1-alpha)*fc+alpha*fo;
scale=max(1,sum(abs(n).*abs(F)));tol=u'*abs(F)+512*eps*scale;
if abs(n'*F)>tol,error('LH2:MethodRTangency','Averaged pressure tangency failed');end
keep=true(size(x));keep(mode.context.index)=false;omitted=-sum(n(keep).*F(keep))/n(mode.context.index)-F(mode.context.index);
if abs(omitted)>512*eps*max(1,norm(F,inf)),error('LH2:MethodROmittedRow','Algebraic omitted row failed');end
names=fieldnames(lc);flux=lc;for k=1:numel(names),flux.(names{k})=(1-alpha)*lc.(names{k})+alpha*lo.(names{k});end
d.bits(i)=NaN;d.weights(i)=alpha;d.alpha=alpha;d.a=a;d.b=b;d.constraintResidual=rd.residual;d.chartDifference=rd.coordinateDifference;d.omittedResidual=omitted;d.flux=flux;
if audit
 if alpha < -1024*eps||alpha>1+1024*eps,error('LH2:MethodRWeight','Accepted sliding weight inadmissible');end
 d.independentOmitted=m.verify(t,xc,mode.context,F,n);
end
end
function [mode,entry]=initialize(m,t,x,handoff)
% Shared pure initial-mode path for static verification and actual integration.
if nargin<4,handoff=[];end
x=x(:);g=m.surfaces(t,x);before=struct('bits',double(g(:)'>0),'active',0,'context',[]);mode=before;
entry=struct('record',[],'provenance',[],'chartDiscrepancy',zeros(size(x)));
if m.domain(t,x)>=0,error('LH2:MethodRDomain','Receiver pressure-domain stop');end
if isempty(handoff)
 exact=find(g==0);
 for i=exact(:)',q=classify(m,t,x,mode.bits,i);mode=enter(m,t,x,mode,i,q);end
 ids=exact(:)'+1;
else
 if ~isfield(m,'validateHandoff'),error('LH2:HandoffProvenance','Problem has no accepted-ledger validator');end
 info=m.validateHandoff(handoff,t,x);i=info.tank;c=m.context(t,x,i);
 if ~isfield(c,'target')||~isequal(c.target,info.target),error('LH2:HandoffTarget','Chart target differs from accepted target');end
 if ~isfield(c,'Bp')||abs(g(i))>c.Bp,error('LH2:HandoffResidual','Accepted residual exceeds the chart allocation');end
 q=classify(m,t,x,mode.bits,i);
 if ~strcmp(q.kind,'sliding'),error('LH2:HandoffNotAttracting','Accepted handoff lacks resolved strict attraction');end
 others=unique([info.tanks(:);find(g==0)]);
 for other=others(:)'
  if other==i,continue;end
  qOther=classify(m,t,x,mode.bits,other);
  if strcmp(qOther.kind,'sliding'),error('LH2:MethodRSimultaneousUnsupported','Joint attracting surfaces are not implemented');end
  mode.bits(other)=qOther.bit;
 end
 [represented,~]=m.chart(t,x,c);entry.chartDiscrepancy=represented-x;
 if max(abs(entry.chartDiscrepancy))>m.coordinateBudget,error('LH2:MethodRBoundary','Accepted handoff chart difference exceeds allocation');end
 mode.active=i;mode.context=c;entry.provenance=info;ids=i+1;
end
if ~isequaln(before,mode)
 entry.record=struct('time',t,'ids',ids,'before',before,'after',mode,'state',x,'chartDiscrepancy',entry.chartDiscrepancy);
end
end
function R=run(m,t0,x0,tf,options,solver,handoff)
if nargin<7,handoff=[];end
x0=x0(:);g=m.surfaces(t0,x0);mode=struct('bits',double(g(:)'>0),'active',0,'context',[]);clock=tic;calls=0;transactions=0;
R=struct('t',t0,'x',x0','actions',[],'history',struct('time',{},'ids',{},'before',{},'after',{},'state',{},'chartDiscrepancy',{}),'stopReason','horizon reached; physical completion not certified','failure',[],'segments',{{}});
try
 [mode,entry]=initialize(m,t0,x0,handoff);R.acceptedHandoff=entry.provenance;
 if ~isempty(entry.record),R.history(end+1)=entry.record;end
 [~,d]=field(m,t0,x0,mode,true);R.actions=d;
 while t0<tf
  if toc(clock)>60||transactions>=200,error('LH2:MethodRWorkCap','Final segment/transaction cap');end
  incoming=mode;start=t0;boundary=x0;keep=true(size(x0));
  if mode.active>0
   keep(mode.context.index)=false;initial=x0(keep);[chartStart,~]=m.chart(t0,x0,mode.context);
   discrepancy=chartStart-x0;
   if max(abs(discrepancy))>m.coordinateBudget,error('LH2:MethodRBoundary','Chart changes boundary beyond allocation');end
  else,initial=x0;discrepancy=zeros(size(x0));end
  opts=options;
  if mode.active>0
   atol=odeget(opts,'AbsTol');if numel(atol)>1,opts=odeset(opts,'AbsTol',atol(keep));end
  end
  opts=odeset(opts,'Events',@events);
  if solver==1,sol=ode45(@rhs,[t0 tf],initial,opts);elseif solver==2,sol=ode15s(@rhs,[t0 tf],initial,opts);else,error('LH2:ControlSolverSelection','Unknown solver');end
  ids=[];
  if isfield(sol,'xe')&&~isempty(sol.xe)
   finish=min(sol.xe);ids=unique(reshape(sol.ie(sol.xe==finish),1,[]));
  else
   finish=sol.x(end);if finish<tf,error('LH2:MethodRSolver','Solver returned early without event');end
  end
  endpoint=fullAt(finish);
  times=unique([reshape(sol.x(sol.x>t0&sol.x<finish),[],1);finish]);
  for k=1:numel(times)
   xx=fullAt(times(k));[~,applied]=field(m,times(k),xx,incoming,true);
   R.t(end+1,1)=times(k);R.x(end+1,:)=xx';R.actions(end+1,1)=applied;
  end
  segment=struct('start',start,'finish',finish,'boundary',boundary,'mode',incoming,'chartDiscrepancy',discrepancy,'mesh',sol.x(sol.x<=finish),'solver',solver);
  % Keep the modern interpolation-format marker without retaining RHS closures.
  segment.endpoint=endpoint;segment.solution=sol;segment.solution.extdata=struct;
  R.segments{end+1}=segment;
  if any(ids==1),R.stopReason='receiver pressure domain stop';mode=incoming;
  else
   candidates=ids(ids==2|ids==3)-1;
   if incoming.active>0
    if any(ids==4|ids==5)
     active=incoming.active;[n,u]=m.normal(finish,endpoint,active);bc=incoming.bits;bc(active)=0;bo=incoming.bits;bo(active)=1;
     [fc,~]=m.fields(finish,endpoint,bc);[fo,~]=m.fields(finish,endpoint,bo);a=n'*fc;b=n'*fo;ua=u'*abs(fc);ub=u'*abs(fo);
     if any(ids==4)
      if b>=-ub,error('LH2:MethodRRelease','Release has no resolved inward open field');end
      direction=normalRate(m,finish,endpoint,active,bc,fc);
      if direction>=0,error('LH2:MethodRRelease','Unresolved/touching closed release');end
      mode.active=0;mode.context=[];mode.bits(active)=0;
     else
      if a<=ua,error('LH2:MethodRRelease','Release has no resolved inward closed field');end
      direction=normalRate(m,finish,endpoint,active,bo,fo);
      if direction<=0,error('LH2:MethodRRelease','Unresolved/touching open release');end
      mode.active=0;mode.context=[];mode.bits(active)=1;
     end
    end
   end
   for i=candidates(:)'
    q=classify(m,finish,endpoint,mode.bits,i);mode=enter(m,finish,endpoint,mode,i,q);
   end
  end
  R.history(end+1)=struct('time',finish,'ids',ids,'before',incoming,'after',mode,'state',endpoint,'chartDiscrepancy',discrepancy);
  [~,R.actions(end)]=field(m,finish,endpoint,mode,true);
  transactions=transactions+1;
  if any(ids==1),break;end
  if finish==t0,error('LH2:MethodRZeroTime','Repeated zero-time final-pressure transaction');end
  t0=finish;x0=endpoint;
 end
catch ME
 R.failure=struct('identifier',ME.identifier,'message',ME.message,'report',getReport(ME,'extended','hyperlinks','off'),'acceptedTime',R.t(end),'acceptedState',R.x(end,:)');
 R.stopReason=['Method R diagnostic stop: ' ME.identifier];
end
R.finalNumericalMode=mode;R.fieldEvaluations=calls;
 function dy=rhs(t,y)
  calls=calls+1;if calls>5000||toc(clock)>60,error('LH2:MethodRWorkCap','Numerical segment cap');end
  x=unpack(t,y);F=field(m,t,x,incoming,false);dy=F(keep);
 end
 function x=unpack(t,y)
  if incoming.active==0,x=y(:);else,x=boundary;x(keep)=y(:);[x,~]=m.chart(t,x,incoming.context);end
 end
 function x=fullAt(t)
  if t==start,x=boundary;else,x=unpack(t,deval(sol,t));end
 end
 function [v,it,dir]=events(t,y)
  x=unpack(t,y);g=m.surfaces(t,x);v=[m.domain(t,x);g(:);1;1];it=ones(5,1);dir=[1;1-2*incoming.bits(:);-1;-1];
  if incoming.active>0
   i=incoming.active;v(i+1)=1;dir(i+1)=0;[n,~]=m.normal(t,x,i);bc=incoming.bits;bc(i)=0;bo=incoming.bits;bo(i)=1;
   [fc,~]=m.fields(t,x,bc);[fo,~]=m.fields(t,x,bo);v(4)=n'*fc;v(5)=-n'*fo;
  end
  for i=1:2
   if incoming.active==i,continue;end
   if t==start&&g(i)==0,v(i+1)=-dir(i+1);
   elseif g(i)==0
    [n,~]=m.normal(t,x,i);[ff,~]=m.fields(t,x,incoming.bits);if (n'*ff)*dir(i+1)<=0,v(i+1)=-dir(i+1);end
   end
  end
 end
end
function mode=enter(m,t,x,mode,i,q)
if strcmp(q.kind,'sliding')
 if mode.active~=0&&mode.active~=i,error('LH2:MethodRSimultaneousUnsupported','Joint attracting surfaces are not implemented');end
 mode.active=i;mode.context=m.context(t,x,i);
else,mode.bits(i)=q.bit;end
end
function rate=normalRate(m,t,x,i,bits,f)
scale=max(abs(x),1);speed=max(abs(f)./scale);if speed==0,error('LH2:MethodRRelease','Stationary unresolved release');end
h=2e-6/speed;xp=x+h*f;xm=x-h*f;[np,~]=m.normal(t,xp,i);[nm,~]=m.normal(t,xm,i);[fp,~]=m.fields(t,xp,bits);[fm,~]=m.fields(t,xm,bits);rate=(np'*fp-nm'*fm)/(2*h);
if ~isfinite(rate)||rate==0,error('LH2:MethodRRelease','Directional release unresolved');end
end

function x=dense(m,segment,times)
x=zeros(numel(segment.boundary),numel(times));
for j=1:numel(times)
 t=times(j);if t<segment.start||t>segment.finish,error('LH2:MethodRDenseDomain','Dense query outside accepted segment');end
 if t==segment.start,x(:,j)=segment.boundary;elseif t==segment.finish,x(:,j)=segment.endpoint;else
  y=deval(segment.solution,t);if segment.mode.active==0,x(:,j)=y;else
   xx=segment.boundary;keep=true(size(xx));keep(segment.mode.context.index)=false;xx(keep)=y;[x(:,j),~]=m.chart(t,xx,segment.mode.context);
  end
 end
end
end
