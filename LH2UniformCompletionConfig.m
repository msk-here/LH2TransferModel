function C = LH2UniformCompletionConfig(P,isPump)
% An absent or empty configuration selects the original operating policy.
% Pressure vectors are [source receiver] in absolute Pa.
C = [];
if ~isfield(P,'UniformCompletion') || isempty(P.UniformCompletion)
    return
end
C = P.UniformCompletion;
validateattributes(C,{'struct'},{'scalar'},mfilename,'UniformCompletion');
required = {'pLowPa','pDomainMaxPa','conditioningSeconds','maxWallSeconds', ...
    'maxRhsCalls','maxObserverCalls','maxRows','maxTransactions'};
for k = 1:numel(required)
    name = required{k};
    assert(isfield(C,name),'LH2:UniformMissingInput', ...
        'UniformCompletion.%s must be supplied explicitly. Pressure inputs are absolute Pa.',name);
end
assert(~isfield(C,'pHighPa'),'LH2:UniformDuplicateUpper', ...
    'Set the upper bounds using p_ST_final and p_ET_final in absolute Pa.');
C.pHighPa = [P.p_ST_final P.p_ET_final];
for name = {'pLowPa','pHighPa','pDomainMaxPa'}
    key = name{1};
    validateattributes(C.(key),{'numeric'},{'real','finite','positive','size',[1 2]},mfilename,key);
end
validateattributes(P.p_atm,{'numeric'},{'real','finite','positive','scalar'},mfilename,'p_atm');
assert(all(C.pLowPa < C.pHighPa),'LH2:UniformPressureOrder', ...
    'Each conditioning pair requires 0 < pLowPa < its existing final pressure in absolute Pa.');
assert(all(C.pLowPa > P.p_atm) && all(C.pHighPa < C.pDomainMaxPa), ...
    'LH2:UniformPressureDomain','Require p_atm < pLowPa and upper bounds below the supplied domain maxima.');
if isfield(P,'p_c')
    assert(all(C.pDomainMaxPa <= P.p_c),'LH2:UniformPressureDomain', ...
        'Conditioning domain maxima must not exceed the configured critical reference.');
end
if isfield(C,'pOperatingMaxPa')
    validateattributes(C.pOperatingMaxPa,{'numeric'}, ...
        {'real','finite','positive','size',[1 2]},mfilename,'pOperatingMaxPa');
    assert(all(C.pHighPa < C.pOperatingMaxPa),'LH2:UniformOperatingLimit', ...
        'Operational stop bounds must exceed the configured vent-opening pressures.');
else
    C.pOperatingMaxPa = [Inf Inf];
end
for name = {'conditioningSeconds','maxWallSeconds'}
    validateattributes(C.(name{1}),{'numeric'}, ...
        {'real','finite','positive','scalar'},mfilename,name{1});
end
for name = {'maxRhsCalls','maxObserverCalls','maxRows','maxTransactions'}
    validateattributes(C.(name{1}),{'numeric'}, ...
        {'real','finite','positive','scalar','integer'},mfilename,name{1});
end
if isPump
    assert(isfield(C,'passivePumpHeat') && ...
        (ischar(C.passivePumpHeat) || isstring(C.passivePumpHeat)) && ...
        any(strcmp(C.passivePumpHeat,{'retain','disconnect'})) && isscalar(string(C.passivePumpHeat)), ...
        'LH2:UniformPumpHeat','Choose passivePumpHeat explicitly: retain or disconnect.');
end
end
