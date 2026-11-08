function varargout=LH2PressureChart(action,varargin)
%LH2PRESSURECHART Local, empirical pressure coordinates. No physical resets.
switch action
 case 'normal',[varargout{1:nargout}]=normal(varargin{:});
 case 'context',varargout{1}=context(varargin{:});
 case 'root',[varargout{1:nargout}]=root(varargin{:});
 case 'verify',varargout{1}=verify(varargin{:});
 otherwise,error('LH2:MethodRAction','Unknown pressure chart action');
end
end
function [n,u,meta]=normal(observe,t,x,i)
s=valid(observe,t,x,i);meta=s.chart(i);idx=meta.indices;n=zeros(numel(x),1);u=n;
for k=1:4
 scale=max(abs(x(idx(k))),1);h=[7e-6 2e-6]*scale;d=zeros(1,2);
 for j=1:2
  xp=x;xm=x;xp(idx(k))=xp(idx(k))+h(j);xm(idx(k))=xm(idx(k))-h(j);
  sp=valid(observe,t,xp,i);sm=valid(observe,t,xm,i);d(j)=(pressure(sp,i)-pressure(sm,i))/(2*h(j));
 end
 if abs(d(1)-d(2))>1e-5*max(abs(d(2)),1e-12)+1e-7/h(2)
  error('LH2:MethodRNormalUncertain','Pressure partial is unresolved');
 end
 n(idx(k))=d(2);u(idx(k))=abs(d(1)-d(2))+1e-7/h(2);
end
r=idx(3);
if ~(n(r)>0&&u(r)<=1e-5*n(r))
 error('LH2:MethodRConditioning','Vapor-mass inverse lacks resolved positive sensitivity');
end
end
function c=context(observe,t,x,i,target)
[n,u,meta]=normal(observe,t,x,i);idx=meta.indices;c.tank=i;c.index=idx(3);c.reference=x(:);c.other=idx([1 2 4]);
c.box=[1e-6;1e-6;3e-8].*max(abs(x(c.other)),1);c.Bm=1e-10;c.Bp=n(c.index)*c.Bm/4;c.target=target;
if c.Bp<1e-7,error('LH2:MethodRConditioning','Pressure allocation below local observer guard');end
width=4*sum(abs(n(c.other)).*c.box)/n(c.index);c.bracket=x(c.index)+[-width width];c.normal=n;c.normalUncertainty=u;
if width<=0||c.bracket(1)<=0,error('LH2:MethodRRootBracket','No positive fixed root bracket');end
end
function [x,d]=root(observe,t,guess,c)
x=guess(:);
if any(abs(x(c.other)-c.reference(c.other))>c.box)
 error('LH2:MethodRChartDomain','Local pressure chart box exhausted');
end
x(c.index)=c.reference(c.index);s=valid(observe,t,x,c.tank);g=pressure(s,c.tank)-c.target;calls=1;iterations=0;
if abs(g)>c.Bp
 lo=c.bracket(1);hi=c.bracket(2);xl=x;xh=x;xl(c.index)=lo;xh(c.index)=hi;
 sl=valid(observe,t,xl,c.tank);sh=valid(observe,t,xh,c.tank);gl=pressure(sl,c.tank)-c.target;gh=pressure(sh,c.tank)-c.target;calls=calls+2;
 if ~(gl<0&&gh>0),error('LH2:MethodRRootBracket','Fixed bracket does not contain directed pressure root');end
 ok=false;
 for iterations=1:40
  r=lo+(hi-lo)/2;x(c.index)=r;s=valid(observe,t,x,c.tank);g=pressure(s,c.tank)-c.target;calls=calls+1;
  if abs(g)<=c.Bp&&hi-lo<=c.Bm/2,ok=true;break;end
  if g<0,lo=r;else,hi=r;end
 end
 if ~ok,error('LH2:MethodRRootWork','Root work cap reached');end
end
repeat=valid(observe,t,x,c.tank);
if ~isequaln(pressure(repeat,c.tank)-c.target,g)
 error('LH2:MethodRNondeterministic','Repeated pressure reconstruction changed at identical full state');
end
calls=calls+1;
d=struct('residual',g,'coordinateDifference',x(c.index)-guess(c.index),'calls',calls,'iterations',iterations,'Bp',c.Bp,'Bm',c.Bm);
end
function d=verify(observe,t,x,c,F,n)
keep=true(size(x));keep(c.index)=false;moving=abs(F(c.other))>0;
if any(moving),h=.25*min(c.box(moving)./abs(F(c.other(moving))));else,h=1e-3;end
xp=x;xm=x;xp(keep)=x(keep)+h*F(keep);xm(keep)=x(keep)-h*F(keep);
[xp,~]=root(observe,t,xp,c);[xm,~]=root(observe,t,xm,c);fd=(xp(c.index)-xm(c.index))/(2*h);
scale=max(abs(F(c.index)),1e-6);budget=.01*scale+2*c.Bm/h;
if budget>.05*scale,error('LH2:MethodROmittedUncertain','Independent omitted-row allocation is unresolved');end
if abs(fd-F(c.index))>budget,error('LH2:MethodROmittedRow','Independent chart derivative disagrees with physical row');end
d=struct('finiteDifference',fd,'physicalRow',F(c.index),'residual',fd-F(c.index),'budget',budget,'step',h,'algebraic',-sum(n(keep).*F(keep))/n(c.index)-F(c.index));
end
function s=valid(observe,t,x,i)
s=observe(t,x);
if ~isfield(s,'chart')||numel(s.chart)<i
 error('LH2:MethodRObserverContract','Observer lacks authoritative pressure provenance');
end
if ~isfinite(pressure(s,i))||~isreal(pressure(s,i))
 error('LH2:MethodRNonfinite','Pressure observer returned nonfinite or complex pressure');
end
if ~s.chart(i).regular
 error('LH2:MethodRUnsupportedProperty','Only fallback-free superheated positive-inventory pressure charts are supported');
end
end
function p=pressure(s,i)
if i==1,p=s.p1;else,p=s.p2;end
end
