function value=LH2AcceptedEvent(action,varargin)
%LH2ACCEPTEDEVENT Explicit adapter for a caller-owned accepted controller ledger.
% This is a software provenance contract, not authentication of arbitrary input.
switch action
 case 'fromHistory'
  P=varargin{1};z=varargin{2};ledger=varargin{3};tank=varargin{4};
  if isempty(ledger),error('LH2:HandoffProvenance','An accepted ledger is required');end
  targets=[P.p_ST_final P.p_ET_final];
  if ~isscalar(tank)||~ismember(tank,[1 2]),error('LH2:HandoffTank','Invalid tank');end
  value=struct('version',1,'tank',tank,'target',targets(tank),'controller',z,'ledger',ledger,'index',numel(ledger),'record',ledger(end));
 case 'validate'
  P=varargin{1};z=varargin{2};h=varargin{3};t=varargin{4};x=varargin{5};
  required={'version','tank','target','controller','ledger','index','record'};
  if ~isstruct(h)||~isscalar(h)||~all(isfield(h,required))||h.version~=1,error('LH2:HandoffProvenance','Invalid accepted-event descriptor');end
  if ~isscalar(h.tank)||~ismember(h.tank,[1 2]),error('LH2:HandoffTank','Invalid tank');end
  if isempty(h.ledger)||h.index~=numel(h.ledger)||~isequaln(h.record,h.ledger(end)),error('LH2:HandoffProvenance','Candidate is not the latest accepted ledger record');end
  e=h.record;tail=h.ledger(end);
  if ~isa(e.state,'double')||~isa(tail.state,'double')||~isequal(typecast(e.state(:),'uint64'),typecast(tail.state(:),'uint64')),error('LH2:HandoffProvenance','Candidate differs bitwise from the accepted ledger state');end
  if ~all(isfield(e,{'time','state','ids','before','after'})),error('LH2:HandoffProvenance','Incomplete accepted record');end
  if ~isequal(e.time,t)||any([h.ledger.time]>t),error('LH2:HandoffTime','Accepted event is stale or has a different clock');end
  if ~isa(x,'double')||~isa(e.state,'double')||~isequal(typecast(x(:),'uint64'),typecast(e.state(:),'uint64')),error('LH2:HandoffState','Accepted event state differs bitwise');end
  if ~isequaln(h.controller,z)||~isequaln(e.after,z)||~isfield(z,'final')||~z.final||~isfield(z,'ready')||z.ready||~isstruct(e.before)||~isfield(e.before,'final')||~e.before.final,error('LH2:HandoffController','Accepted final controller mode is inconsistent');end
  if isempty(e.ids)||any(~ismember(e.ids,[10 11 13 14])),error('LH2:HandoffPriority','Not an unoverridden final-pressure transaction');end
  if ~any(ismember(e.ids,[9+h.tank 12+h.tank])),error('LH2:HandoffTank','Accepted pressure event belongs to another tank');end
  if any(e.ids==9+h.tank)
   names={'tSourceFirst','tReceiverFirst'};name=names{h.tank};
   if ~isfield(z,name)||~isequal(z.(name),t),error('LH2:HandoffProvenance','First attainment does not match this accepted transaction');end
  end
  targets=[P.p_ST_final P.p_ET_final];
  if ~isequal(h.target,targets(h.tank)),error('LH2:HandoffTarget','Final-pressure target differs');end
  tanks=[];for i=1:2,if any(ismember(e.ids,[9+i 12+i])),tanks(end+1)=i;end;end
  value=struct('tank',h.tank,'tanks',tanks,'time',t,'state',x(:),'eventIds',e.ids,'target',h.target,'historyLength',numel(h.ledger));
 otherwise,error('LH2:HandoffAction','Unknown accepted-event action');
end
end
