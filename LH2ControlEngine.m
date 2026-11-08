function varargout = LH2ControlEngine(action,varargin)
%LH2CONTROLENGINE Deterministic controller modes and segmented integration.
%
% No physical state jumps, settling cutoff, or physical completion claim.
% Event IDs:
%  1 receiver domain stop
%  2 filling target
%  3 stage downward
%  4 stage upward
%  5 PD readiness
%  6 source filling vent
%  7 receiver filling vent
%  8 vaporizer lower boundary
%  9 vaporizer upper boundary
% 10 first source final-pressure attainment
% 11 first receiver final-pressure attainment
% 12 scheduled pump startup (driver-owned)

switch lower(action)
    case 'init'
        varargout{1} = initializeControlMode(varargin{:});
    case 'inputs'
        varargout{1} = evaluateControlInputs(varargin{:});
    case 'events'
        [varargout{1:nargout}] = evaluateControlEvents(varargin{:});
    case 'commit'
        varargout{1} = commitControlTransition(varargin{:});
    case 'sample'
        varargout{1} = makeControlSample(varargin{:});
    case 'run'
        varargout{1} = integrateControlSegments(varargin{:});
    otherwise
        error('LH2:ControlEngineAction','Unknown action: %s',action);
end
end

function b = fillingStageBoundaries(isPump)
if isPump
    b = [0.15 0.70 0.85];
else
    b = [0.05 0.70 0.85];
end
end

function k = selectFillStage(q,isPump)
k = 1 + sum(q >= fillingStageBoundaries(isPump));
end

function [pSet,pLow,pHigh] = activePressureReferences(P,z)
if z.isPump
    pSet = P.p_ST_min;
    pLow = P.p_ST_low;
    pHigh = P.p_ST_high;
else
    if z.stage == 2
        pSet = P.p_ST_fast;
    else
        pSet = P.p_ST_slow;
    end
    pLow = 0.98*pSet;
    pHigh = 1.10*pSet;
end
end

function yes = vaporizerSupportEnabled(z)
% Preserve the pre-existing stationary-host distinction:
% PD stationary runs disable the vaporizer; pump stationary runs do not.
% Shutdown/blowdown disables new inlet demand in both hosts.
yes = ~z.final && (z.transferEnabled || z.isPump);
end

function [region,memory] = initializeVaporizerMemory(p,pSet,memory)
if p < 0.98*pSet
    region = -1;                 % proportional tracking
elseif p > 1.02*pSet
    region = 1;                  % zero command
    memory = 0;
else
    region = 0;                  % fractional hold
end
end

function value = normalizeVentState(value,p,low,high)
if p < low
    value = 0;
elseif p > high
    value = 1;
end
% Static equality retains incoming memory.
end

function z = initializeControlMode(P,isPump,transferEnabled,s,t)
z.isPump = logical(isPump);
z.transferEnabled = logical(transferEnabled);

z.blowdown = isfield(P,'caseNumber') && P.caseNumber == 6;
if ~isfield(P,'caseNumber') && isfield(P,'name')
    z.blowdown = startsWith(string(P.name),"ExternalTankInitialBlowdown");
end

z.stage = selectFillStage(s.q,z.isPump);
z.fillReached = ~z.blowdown && s.q >= P.TopET;
z.final = z.blowdown || z.fillReached;
z.ready = false;

z.sourceOpen = double(logical(P.STVentState));
z.receiverOpen = double(logical(P.ETVentState));
z.vapMemory = P.VapValveState;
z.vapRegion = 0;

z.tFill = NaN;
z.tShutdown = NaN;
z.tSourceFirst = NaN;
z.tReceiverFirst = NaN;
z.entryTime = NaN;
z.entryEvents = [];

if z.fillReached
    z.tFill = t;
end
if z.final
    z.tShutdown = t;
    z.vapMemory = 0;
    z.vapRegion = 1;
else
    if z.transferEnabled
        if z.isPump
            z.ready = t >= 5;
        else
            z.ready = s.p1 > min(P.p_ST_slow,P.p_ST_fast);
        end
    end

    [pSet,low,high] = activePressureReferences(P,z);
    z.sourceOpen = normalizeVentState( ...
        z.sourceOpen,s.p1,low,high);
    z.receiverOpen = normalizeVentState( ...
        z.receiverOpen,s.p2,P.p_ET_low,P.p_ET_high);

    if vaporizerSupportEnabled(z)
        [z.vapRegion,z.vapMemory] = ...
            initializeVaporizerMemory(s.p1,pSet,z.vapMemory);
    else
        z.vapRegion = 1;
        z.vapMemory = 0;
    end
end

z = updatePressureAttainment(P,z,s,t,[]);
end

function U = evaluateControlInputs(P,z,p1,p2)
if z.isPump
    r = P.PumpMassTransferSlow/P.PumpMassTransferFast;
    factors = [r 1 0.8 0.8*r];
else
    factors = [0.5 1 0.8 0.7];
end

U.lambdaE = factors(z.stage)*double( ...
    z.transferEnabled && ~z.final);
U.lambdaV = 0;

if isfield(z,'conditioningOpen')
    U.STVentState = double(z.conditioningOpen(1));
    U.ETVentState = double(z.conditioningOpen(2));
    return
end

if z.final
    if isfield(z,'finalVentBinary')
        bits=z.finalVentBinary;
        assert(numel(bits)==2&&all(bits==0|bits==1),'LH2:MethodRBinaryMask','Explicit branches must be binary.');
        U.STVentState=bits(1);U.ETVentState=bits(2);return
    end
    if isfield(z,'finalNumerical')&&~isempty(z.finalNumerical)&&z.finalNumerical.active>0
        error('LH2:MethodRBranchRequired','Sliding requires complete explicit binary fields.');
    end
    U.STVentState = double(p1 > P.p_ST_final);
    U.ETVentState = double(p2 > P.p_ET_final);
    return
end

U.STVentState = z.sourceOpen;
U.ETVentState = z.receiverOpen;

if vaporizerSupportEnabled(z)
    [pSet,~,~] = activePressureReferences(P,z);
    if z.vapRegion < 0
        U.lambdaV = min(1,max(0,10*(pSet-p1)/pSet));
    elseif z.vapRegion == 0
        U.lambdaV = z.vapMemory;
    end
end
end

function [value,isterminal,direction] = evaluateControlEvents(P,z,s,t,pStop)
value = ones(11,1);              % disabled surfaces have no zero
isterminal = ones(11,1);
direction = zeros(11,1);

if isfinite(pStop)
    value(1) = s.p2-pStop;
    direction(1) = 1;
end

if ~z.final
    value(2) = s.q-P.TopET;
    direction(2) = 1;

    b = fillingStageBoundaries(z.isPump);
    if z.stage > 1
        value(3) = s.q-b(z.stage-1);
        direction(3) = -1;
    end
    if z.stage < 4
        value(4) = s.q-b(z.stage);
        direction(4) = 1;
    end

    if ~z.isPump && z.transferEnabled && ~z.ready
        value(5) = s.p1-min(P.p_ST_slow,P.p_ST_fast);
        direction(5) = 1;
    end

    [pSet,low,high] = activePressureReferences(P,z);
    if z.sourceOpen
        value(6) = s.p1-low;
        direction(6) = -1;
    else
        value(6) = s.p1-high;
        direction(6) = 1;
    end

    if z.receiverOpen
        value(7) = s.p2-P.p_ET_low;
        direction(7) = -1;
    else
        value(7) = s.p2-P.p_ET_high;
        direction(7) = 1;
    end

    if vaporizerSupportEnabled(z)
        if z.vapRegion < 0
            value(8) = s.p1-0.98*pSet;
            direction(8) = 1;
        elseif z.vapRegion > 0
            value(9) = s.p1-1.02*pSet;
            direction(9) = -1;
        else
            value(8) = s.p1-0.98*pSet;
            direction(8) = -1;
            value(9) = s.p1-1.02*pSet;
            direction(9) = 1;
        end
    end
else
    if isnan(z.tSourceFirst)
        value(10) = s.p1-P.p_ST_final;
        direction(10) = -1;
    end
    if isnan(z.tReceiverFirst)
        value(11) = s.p2-P.p_ET_final;
        direction(11) = -1;
    end
end

% Own the post-transition side at a segment's exact initial endpoint.
% This changes no state or time and introduces no physical deadband.
if t == z.entryTime
    for k = z.entryEvents
        if direction(k) ~= 0
            value(k) = -direction(k);
        end
    end
end
end

function z = updatePressureAttainment(P,z,s,t,hit)
if ~z.final
    return
end
if isnan(z.tSourceFirst) && ...
        (s.p1 <= P.p_ST_final || any(hit == 10))
    z.tSourceFirst = t;
end
if isnan(z.tReceiverFirst) && ...
        (s.p2 <= P.p_ET_final || any(hit == 11))
    z.tReceiverFirst = t;
end
end

function z = commitControlTransition(P,z,s,t,hit)
old = z;
incoming = evaluateControlInputs(P,old,s.p1,s.p2);
z.entryTime = t;
z.entryEvents = [];

% Domain stop is handled by the driver before this transaction.

% Filling completion precedes stage/readiness/controller transitions.
if ~z.final && (any(hit == 2) || s.q >= P.TopET)
    z.final = true;
    z.fillReached = true;
    z.tFill = t;
    z.tShutdown = t;
end

if z.final
    z.ready = false;
    z.vapRegion = 1;
    z.vapMemory = 0;
    z = updatePressureAttainment(P,z,s,t,hit);
    return
end

% Select the right-hand mode after an accepted directed crossing.
if any(hit == 3)
    z.stage = old.stage-1;
    z.entryEvents(end+1) = 4;
elseif any(hit == 4)
    z.stage = old.stage+1;
    z.entryEvents(end+1) = 3;
else
    z.stage = old.stage;
end

% Readiness cannot override final/blowdown inhibition.
if z.transferEnabled
    if z.isPump
        z.ready = old.ready || t >= 5;
    else
        z.ready = old.ready || any(hit == 5) || ...
            s.p1 > min(P.p_ST_slow,P.p_ST_fast);
    end
end

[pSet,low,high] = activePressureReferences(P,z);
[oldSet,oldLow,oldHigh] = activePressureReferences(P,old);

if low ~= oldLow || high ~= oldHigh
    z.sourceOpen = normalizeVentState( ...
        old.sourceOpen,s.p1,low,high);
else
    if any(hit == 6)
        z.sourceOpen = 1-old.sourceOpen;
    else
        z.sourceOpen = normalizeVentState( ...
            old.sourceOpen,s.p1,low,high);
    end
end

if any(hit == 7)
    z.receiverOpen = 1-old.receiverOpen;
else
    z.receiverOpen = normalizeVentState( ...
        old.receiverOpen,s.p2,P.p_ET_low,P.p_ET_high);
end

if ~vaporizerSupportEnabled(z)
    z.vapRegion = 1;
    z.vapMemory = 0;
elseif pSet ~= oldSet
    [z.vapRegion,z.vapMemory] = ...
        initializeVaporizerMemory(s.p1,pSet,incoming.lambdaV);
elseif any(hit == 8)
    if old.vapRegion < 0
        z.vapRegion = 0;
        z.vapMemory = 0.2;       % limit of 10*(1-0.98)
    else
        z.vapRegion = -1;
    end
    z.entryEvents(end+1) = 8;
elseif any(hit == 9)
    if old.vapRegion > 0
        z.vapRegion = 0;
        z.vapMemory = 0;
    else
        z.vapRegion = 1;
        z.vapMemory = 0;
    end
    z.entryEvents(end+1) = 9;
end
end

function r = makeControlSample(P,z,s,x,applied)
proxy=z;if nargin>=5,proxy.finalVentBinary=applied.mode.bits;end
U = evaluateControlInputs(P,proxy,s.p1,s.p2);
jIndex = P.nL1+P.nV1+4;
bIndex = P.nL1+P.nV1+6;

r.mode = z;
r.p1 = s.p1;
r.p2 = s.p2;
r.hL2 = s.hL2;
r.pointwiseStage = selectFillStage(s.q,z.isPump);
r.lambdaE = U.lambdaE;
r.lambdaV = U.lambdaV;
r.sourceVent = U.STVentState;
r.receiverVent = U.ETVentState;
r.sourceMathematicalWeight=U.STVentState;r.receiverMathematicalWeight=U.ETVentState;
r.appliedConvention='binary';r.constraintResidual=NaN;r.omittedRowResidual=NaN;r.chartRepresentationDifference=0;
r.instantaneousFlux=struct('sourceMass',NaN,'receiverMass',NaN,'sourceEnthalpyOut',NaN,'receiverEnthalpyOut',NaN,'sourceKineticOut',NaN,'receiverKineticOut',NaN);
if nargin>=5
 r.sourceVent=applied.bits(1);r.receiverVent=applied.bits(2);
 r.sourceMathematicalWeight=applied.weights(1);r.receiverMathematicalWeight=applied.weights(2);
 r.instantaneousFlux=applied.flux;r.constraintResidual=applied.constraintResidual;
 r.omittedRowResidual=applied.omittedResidual;r.chartRepresentationDifference=applied.chartDifference;
 if applied.active>0,r.appliedConvention='Filippov complete-field average';end
end

r.Jtr = x(jIndex);
r.Jboil = x(bIndex);
r.remainingTransferMass = NaN;
if z.final && z.transferEnabled && r.Jtr >= 0 && ~isfield(z,'conditioningOpen')
    r.remainingTransferMass = P.tau_tr*r.Jtr;
end
r.sourceFinalCurrentlyAcceptable = s.p1 <= P.p_ST_final;
r.receiverFinalCurrentlyAcceptable = s.p2 <= P.p_ET_final;
r.processCompletionVerified = false;
end

function R = integrateControlSegments(P,x0,isPump,transferEnabled,pStop,solver,rhs,observe,numericalOptions,finalFactory)
% rhs(t,x,z) returns the existing host derivative.
% observe(t,x) returns the host's own pressure/height reconstruction.

if nargin<10,finalFactory=[];end
C = LH2UniformCompletionConfig(P,isPump);
useUniform = ~isempty(C);
t0 = 0;
x0 = x0(:);
z = [];
if useUniform
    rawRhs = rhs;
    rawObserve = observe;
    rhs = @countedRhs;
    observe = @countedObserve;
    clock = tic;
    rhsCalls = 0;
    observerCalls = 0;
    R.uniform = struct('status','NOT_STARTED','entryCause','', ...
        'entryTime',NaN,'deadline',NaN,'completed',false,'errorId','', ...
        'configuration',C,'ports',struct([]), ...
        'boundaries',struct('time',{},'ids',{},'left',{},'right',{}));
    R.t = t0;
    R.x = x0.';
    R.vent = NaN;
    R.control = struct([]);
    R.history = struct([]);
    R.eventNames = {};
    R.solverOptions = [];
    R.solver = solver;
    R.completionBudgetSpecified = false;
    R.methodRSegments = {};
    R.methodRFailure = [];
    R.stopReason = 'NOT_STARTED';
end

try
s = observe(t0,x0);
direct = useUniform && isfield(P,'caseNumber') && P.caseNumber == 6;

if ~direct && isfinite(pStop) && s.p2 >= pStop
    error('LH2:InitialDomainStop', ...
        'Initial receiver pressure is at or above the domain stop.');
end

z = initializeControlMode(P,isPump,transferEnabled,s,t0);
if useUniform && ~direct && (~transferEnabled || z.blowdown || z.fillReached)
    if transferEnabled && z.fillReached && ~z.blowdown
        error('LH2:UniformInitialTarget','The initial target is satisfied without an accepted filling event.');
    end
    error('LH2:UniformOperation','Select a transfer operation or explicit Case 6 direct blowdown.');
end
if direct
    z = enterConditioning(z,s,C,t0);
    z.tShutdown = NaN; % Direct blowdown has no filling-shutdown clock.
    R.uniform.entryCause = 'DIRECT_BLOWDOWN';
    R.uniform.entryTime = t0;
    R.uniform.deadline = conditioningDeadline(t0,C);
    assertUniformDomain(s,P,C);
end

baseOptions = odeset('MaxStep',1,'RelTol',P.relTol, ...
    'AbsTol',1e-6,'Refine',4);
if nargin >= 9 && ~isempty(numericalOptions)
    allowed = {'MaxStep','RelTol','AbsTol','InitialStep','Refine'};
    fields = fieldnames(numericalOptions);
    assert(all(ismember(fields,allowed)),'LH2:ControlSolverOptions', ...
        'Only numerical refinement options may be overridden.');
    baseOptions = odeset(baseOptions,numericalOptions);
end

R.t = t0;
R.x = x0.';
R.control = makeControlSample(P,z,s,x0);
R.vent = R.control.receiverVent;
R.history = struct('time',t0,'ids',0, ...
    'before',[],'after',z,'state',x0);
R.solverOptions = baseOptions;
R.solver = solver;
R.stopReason = 'horizon reached; physical completion not certified';
R.eventNames = {'receiver domain stop','filling target', ...
    'stage downward','stage upward','PD readiness', ...
    'source filling vent','receiver filling vent', ...
    'vaporizer lower boundary','vaporizer upper boundary', ...
    'first source final pressure','first receiver final pressure', ...
    'scheduled pump startup'};
R.completionBudgetSpecified = false;
R.methodRSegments={};R.methodRFailure=[];
R.eventNames=[R.eventNames {'source final operational crossing','receiver final operational crossing','source sliding release','receiver sliding release'}];

sameTimeModes = {z};
if useUniform
    R.eventNames(17:24) = {'source conditioning vent','receiver conditioning vent', ...
        'source conditioning domain','receiver conditioning domain', ...
        'source operational stop','receiver operational stop', ...
        'source downstream-pressure domain','receiver downstream-pressure domain'};
    R.uniform.ports = readPorts(t0,x0,z);
    R.stopReason = 'FILL_TARGET_UNREACHED';
end

while true
    conditioning = isfield(z,'conditioningOpen');
    if conditioning
        if ~any(z.conditioningOpen) && all([s.p1 s.p2] <= C.pHighPa)
            R.stopReason = 'TANK_LEVEL_COMPLETION';
            R.uniform.completed = true;
            break
        end
        if t0 >= R.uniform.deadline
            R.stopReason = 'CONDITIONING_DEADLINE';
            break
        end
    elseif t0 >= P.tFinal
        break
    end
    if z.final && ~conditioning
        if isempty(finalFactory)
            problem=LH2FinalPressureProblem(P,z,rhs,observe,pStop);
        else
            problem=finalFactory(z);
        end
        handoff=[];
        % Only the current accepted pressure transaction can request a handoff.
        last=R.history(end);pressureIds=last.ids(ismember(last.ids,[10 11 13 14]));
        if ~isempty(pressureIds)&&last.time==t0
            tank=1+any(ismember(pressureIds,[11 14]));
            handoff=LH2AcceptedEvent('fromHistory',P,z,R.history,tank);
        end
        E=LH2MethodR('run',problem,t0,x0,P.tFinal,baseOptions,solver,handoff);
        R.methodRSegments=E.segments;R.methodRFailure=E.failure;
        for jj=1:numel(E.t)
            xx=E.x(jj,:)';ss=observe(E.t(jj),xx);
            ledger=find([E.history.time]==E.t(jj));
            for kk=ledger
                e=E.history(kk);before=z;before.finalNumerical=e.before;hit=[];
                for id=e.ids
                    if id==1,hit(end+1)=1;
                    elseif id==2||id==3
                        tank=id-1;hit(end+1)=12+tank;
                        if e.before.bits(tank)==1,hit(end+1)=9+tank;end
                    elseif id==4||id==5,hit(end+1)=14+e.before.active;
                    end
                end
                z=updatePressureAttainment(P,z,ss,E.t(jj),hit);z.finalNumerical=e.after;
                R.history(end+1)=struct('time',E.t(jj),'ids',unique(hit),'before',before,'after',z,'state',xx);
            end
            z=updatePressureAttainment(P,z,ss,E.t(jj),[]);
            if jj==1,row=numel(R.t);else,row=numel(R.t)+1;R.t(row,1)=E.t(jj);R.x(row,:)=xx';end
            if ~isempty(E.actions)
                sampleMode=z;sampleMode.finalNumerical=E.actions(jj).mode;
                R.control(row,1)=makeControlSample(P,sampleMode,ss,xx,E.actions(jj));
            else
                R.control(row,1)=makeControlSample(P,z,ss,xx);
            end
            R.vent(row,1)=R.control(row).receiverVent;
        end
        z.finalNumerical=E.finalNumericalMode;R.stopReason=E.stopReason;break
    end
    segmentEnd = P.tFinal;
    if conditioning
        segmentEnd = R.uniform.deadline;
    end
    if z.isPump && z.transferEnabled && ~z.final && ...
            ~z.ready && t0 < 5
        segmentEnd = min(segmentEnd,5);
    end

    frozen = z;
    events = @(t,x) controllerEventsCallback(P,frozen,t,x,pStop,observe);
    if conditioning
        events = @(t,x) conditioningEventsCallback(P,C,frozen,t,x,observe);
    end
    options = odeset(baseOptions,'Events',events);
    f = @(t,x) rhs(t,x,frozen);

    if solver == 1
        sol = ode45(f,[t0 segmentEnd],x0,options);
    elseif solver == 2
        sol = ode15s(f,[t0 segmentEnd],x0,options);
    else
        error('LH2:ControlSolverSelection','Expected solver selector 1 or 2.');
    end

    hit = [];
    if isfield(sol,'xe') && ~isempty(sol.xe)
        tEnd = min(sol.xe);
        hit = unique(reshape(sol.ie(sol.xe == tEnd),1,[]));
        xEnd = deval(sol,tEnd);
    else
        tEnd = sol.x(end);
        xEnd = sol.y(:,end);
        if tEnd < segmentEnd
            error('LH2:ControlSolverStoppedEarly', ...
                'Solver returned before its endpoint without an event.');
        end
    end

    if useUniform
        R.uniform.candidateEndpoint = struct('time',tEnd,'state',xEnd,'ids',hit);
    end

    % Never retain a post-event portion computed with obsolete modes.
    tt = sol.x(sol.x > t0 & sol.x < tEnd);
    tt = unique([tt(:); tEnd]);
    tt = tt(tt > t0);
    for j = 1:numel(tt)
        xx = deval(sol,tt(j));
        ss = observe(tt(j),xx);
        if useUniform
            checkWork();
            if numel(R.t) >= C.maxRows
                error('LH2:UniformResourceCap','Accepted output row cap reached.');
            end
            if conditioning
                assertUniformDomain(ss,P,C);
            end
            rowPorts = readPorts(tt(j),xx,frozen);
            R.uniform.ports(end+1,1) = rowPorts;
        end
        R.t(end+1,1) = tt(j);
        R.x(end+1,:) = xx.';
        R.control(end+1,1) = makeControlSample(P,frozen,ss,xx);
        R.vent(end+1,1) = R.control(end).receiverVent;
    end

    sEnd = observe(tEnd,xEnd);

    % Include exactly zero coincident enabled surfaces without inventing
    % a physical or temporal coincidence tolerance.
    if conditioning
        [v,~,d] = conditioningEvents(P,C,frozen,sEnd);
    else
        [v,~,d] = evaluateControlEvents(P,frozen,sEnd,tEnd,pStop);
    end
    previous = find(sol.x < tEnd,1,'last');
    if ~isempty(previous)
        vp = events(sol.x(previous),sol.y(:,previous));
        crossed = v == 0 & d ~= 0 & vp.*d < 0;
        hit = unique([hit, find(crossed).']);
    end

    if frozen.isPump && frozen.transferEnabled && ...
            ~frozen.final && ~frozen.ready && tEnd == 5
        hit = unique([hit 12]);
    end

    if conditioning && any(ismember(hit,[19 20 23 24]))
        error('LH2:UniformDomainStop','Accepted conditioning pressure-domain event.');
    end
    if conditioning && any(ismember(hit,[21 22]))
        error('LH2:UniformOperationalStop','Accepted conditioning operational pressure event.');
    end
    if useUniform && numel(R.history)-1 >= C.maxTransactions
        error('LH2:UniformResourceCap','Accepted transaction cap reached.');
    end
    if any(hit == 1)
        R.history(end+1) = struct('time',tEnd,'ids',hit, ...
            'before',frozen,'after',frozen,'state',xEnd);
        R.stopReason = 'receiver pressure domain stop';
        if useUniform
            R.stopReason = 'THERMODYNAMIC_DOMAIN_STOP';
        end
        break
    end

    entering = false;
    if conditioning
        assertUniformDomain(sEnd,P,C);
        next = frozen;
        tanks = hit(ismember(hit,[17 18]))-16;
        next.conditioningOpen(tanks) = ~frozen.conditioningOpen(tanks);
        closedNow = tanks(~next.conditioningOpen(tanks));
        openedNow = tanks(next.conditioningOpen(tanks));
        next.conditioningSatisfiedSince(closedNow) = tEnd;
        next.conditioningLastLowTime(closedNow) = tEnd;
        next.conditioningSatisfiedSince(openedNow) = NaN;
        p = [sEnd.p1 sEnd.p2];
        missed = (~next.conditioningOpen & p > C.pHighPa) | ...
            (next.conditioningOpen & p <= C.pLowPa);
        assert(~any(missed),'LH2:UniformEventUnresolved', ...
            'Accepted pressure and vent memory disagree; a directed crossing is unresolved.');
        if isempty(tanks)
            t0 = tEnd;
            x0 = xEnd;
            s = sEnd;
            continue
        end
    else
        if useUniform && sEnd.q >= P.TopET && ~any(hit == 2)
            error('LH2:UniformEventUnresolved','Filling target requires an accepted directed event.');
        end
        next = commitControlTransition(P,frozen,sEnd,tEnd,hit);
        entering = useUniform && any(hit == 2);
        if entering
            next = enterConditioning(next,sEnd,C,tEnd);
            assertUniformDomain(sEnd,P,C);
        end
    end
    if entering || conditioning
        rightPorts = readPorts(tEnd,xEnd,next);
        record = struct('time',tEnd,'ids',hit,'left',R.uniform.ports(end),'right',rightPorts);
        R.uniform.boundaries(end+1,1) = record;
        R.uniform.ports(end) = rightPorts;
        if entering
            R.uniform.entryCause = 'ACCEPTED_FILL_TARGET';
            R.uniform.entryTime = tEnd;
            R.uniform.deadline = conditioningDeadline(tEnd,C);
        end
    end

    if tEnd == t0
        repeated = any(cellfun(@(a) isequaln(a,next),sameTimeModes));
        if repeated
            error('LH2:ControlZeroTimeModeCycle', ...
                'Repeated same-time controller mode; no state/time nudge applied.');
        end
        sameTimeModes{end+1} = next;
    else
        sameTimeModes = {next};
    end

    R.history(end+1) = struct('time',tEnd,'ids',hit, ...
        'before',frozen,'after',next,'state',xEnd);

    % Raw row at the boundary represents the committed right-hand mode;
    % the event ledger preserves the incoming mode separately.
    R.control(end) = makeControlSample(P,next,sEnd,xEnd);
    R.vent(end) = R.control(end).receiverVent;

    t0 = tEnd;
    x0 = xEnd;
    z = next;
    s = sEnd;

    if isfield(P,'waitbar') && isgraphics(P.waitbar)
        waitbar(min(t0/P.tFinal,1),P.waitbar);
    end
end

catch err
    if ~useUniform
        rethrow(err)
    end
    R.uniform.errorId = err.identifier;
    R.uniform.errorMessage = err.message;
    switch err.identifier
        case 'LH2:UniformResourceCap'
            R.stopReason = 'RESOURCE_CAP';
        case {'LH2:UniformDomainStop','LH2:InitialDomainStop'}
            R.stopReason = 'THERMODYNAMIC_DOMAIN_STOP';
        case 'LH2:UniformOperationalStop'
            R.stopReason = 'OPERATIONAL_PRESSURE_STOP';
        case 'LH2:UniformInitialTarget'
            R.stopReason = 'INITIAL_TARGET_SATISFIED';
        case 'LH2:UniformOperation'
            R.stopReason = 'OPERATION_NOT_APPLICABLE';
        case 'LH2:UniformEventUnresolved'
            R.stopReason = 'EVENT_UNRESOLVED';
        otherwise
            R.stopReason = 'SOLVER_OR_MODEL_FAILURE';
    end
end
R.finalMode = z;
if useUniform
    R.uniform.status = R.stopReason;
    R.uniform.work = struct('rhsCalls',rhsCalls,'observerCalls',observerCalls, ...
        'elapsedSeconds',toc(clock));
end

    function checkWork()
        if toc(clock) >= C.maxWallSeconds
            error('LH2:UniformResourceCap','Controller wall-time cap reached.');
        end
    end

    function varargout = countedRhs(varargin)
        checkWork();
        if rhsCalls >= C.maxRhsCalls
            error('LH2:UniformResourceCap','RHS call cap reached.');
        end
        rhsCalls = rhsCalls + 1;
        [varargout{1:nargout}] = rawRhs(varargin{:});
        fValue = varargout{1};
        assert(isreal(fValue) && all(isfinite(fValue)), ...
            'LH2:UniformNonfiniteRHS','RHS returned a nonfinite or complex derivative.');
        checkWork();
    end

    function observed = countedObserve(t,x)
        checkWork();
        if observerCalls >= C.maxObserverCalls
            error('LH2:UniformResourceCap','Observer call cap reached.');
        end
        observerCalls = observerCalls + 1;
        observed = rawObserve(t,x);
        checkWork();
    end

    function ports = readPorts(t,x,mode)
        [~,~,~,ports] = rhs(t,x,mode);
        inputs = evaluateControlInputs(P,mode,ports.pressurePa(1),ports.pressurePa(2));
        ports.ventCommand = [inputs.STVentState inputs.ETVentState];
    end
end

function z = enterConditioning(z,s,C,t)
z.conditioningOpen = [s.p1 s.p2] > C.pHighPa;
z.conditioningSatisfiedSince = [NaN NaN];
z.conditioningSatisfiedSince(~z.conditioningOpen) = t;
z.conditioningLastLowTime = [NaN NaN];
end

function deadline = conditioningDeadline(t,C)
deadline = t+C.conditioningSeconds;
assert(isfinite(deadline) && deadline > t,'LH2:UniformOperation', ...
    'Conditioning duration must give a finite, representable deadline.');
end

function assertUniformDomain(s,P,C)
p = [s.p1 s.p2];
if ~s.conditioningDomainOK || ~isreal(p) || any(~isfinite(p)) || ...
        any(p <= P.p_atm) || any(p >= C.pDomainMaxPa)
    error('LH2:UniformDomainStop','Conditioning pressure or thermodynamic state outside the supported domain.');
end
if any(p >= C.pOperatingMaxPa)
    error('LH2:UniformOperationalStop','Conditioning operational pressure stop reached.');
end
end

function [v,it,d] = conditioningEventsCallback(P,C,z,t,x,observe)
[v,it,d] = conditioningEvents(P,C,z,observe(t,x));
end

function [v,it,d] = conditioningEvents(P,C,z,s)
v = ones(24,1);
it = ones(size(v));
d = zeros(size(v));
p = [s.p1 s.p2];
threshold = C.pHighPa;
threshold(z.conditioningOpen) = C.pLowPa(z.conditioningOpen);
v(17:18) = p-threshold;
d(17:18) = 1-2*double(z.conditioningOpen);
v(19:20) = p-C.pDomainMaxPa;
d(19:20) = 1;
for i = 1:2
    if isfinite(C.pOperatingMaxPa(i))
        v(20+i) = p(i)-C.pOperatingMaxPa(i);
        d(20+i) = 1;
    end
end
v(23:24) = p-P.p_atm;
d(23:24) = -1;
end

function [v,it,d] = controllerEventsCallback(P,z,t,x,pStop,observe)
s = observe(t,x);
[v,it,d] = evaluateControlEvents(P,z,s,t,pStop);
end
