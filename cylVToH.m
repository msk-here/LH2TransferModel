    %Cylinder height function added by JMB
function H = cylVToH(V,R,L)
%CYLVTOH Invert horizontal-cylinder volume without clipping inventory.
% COMMIT_003: |Vgeom(H)-V| <= 1e-8*pi*R^2*L.
validateattributes(V, {'numeric'}, {'real','finite','scalar'}, ...
    mfilename, 'V');
validateattributes(R, {'numeric'}, {'real','finite','scalar','positive'}, ...
    mfilename, 'R');
validateattributes(L, {'numeric'}, {'real','finite','scalar','positive'}, ...
    mfilename, 'L');

V = double(V);
R = double(R);
L = double(L);
Vtank = pi*R^2*L;
validateattributes(Vtank, {'double'}, ...
    {'real','finite','scalar','positive'}, mfilename, 'Vtank');
validateattributes(2*R, {'double'}, ...
    {'real','finite','scalar','positive'}, mfilename, '2R');

if V < 0 || V > Vtank
    error('LH2:CylinderVolumeDomain', ...
        'Require 0 <= V <= pi*R^2*L; V=%.17g, Vtank=%.17g m^3.', ...
        V, Vtank);
end

if V == 0
    H = 0;
    return
elseif V == Vtank
    H = 2*R;
    return
elseif V == Vtank/2
    H = R;
    return
end

volumeTol = 1e-8*Vtank;
if volumeTol == 0
    error('LH2:CylinderNumericalScale', ...
        'Cylinder volume is too small to represent its error budget.');
end

% Solve the smaller cap: q is cap depth divided by R, in [0,1].
upperHalf = V > Vtank/2;
if upperHalf
    target = (Vtank-V)/Vtank;
else
    target = V/Vtank;
end

lo = 0;
hi = 1;
maxIter = 64;

for iter = 1:maxIter
    q = lo + (hi-lo)/2;
    capFraction = cylSegmentFraction(q);

    if upperHalf
        H = R + R*(1-q);
        qReturned = (2*R-H)/R;
        Vgeom = Vtank - Vtank*cylSegmentFraction(qReturned);
    else
        H = R*q;
        qReturned = H/R;
        Vgeom = Vtank*cylSegmentFraction(qReturned);
    end

    % Check the actual returned height, including reflection roundoff.
    if isfinite(Vgeom) && abs(Vgeom-V) <= volumeTol
        return
    end

    if capFraction < target
        lo = q;
    else
        hi = q;
    end
end

error('LH2:CylinderInversionFailure', ...
    'Cylinder inverse failed after %d iterations; residual=%.17g m^3, budget=%.17g m^3.', ...
    maxIter, abs(Vgeom-V), volumeTol);
end

function fraction = cylSegmentFraction(q)
% Small-cap volume / full-cylinder volume, for cap depth/R in [0,1].
if ~isfinite(q) || q < 0 || q > 1
    error('LH2:CylinderCapDomain', ...
        'Normalized cylinder cap depth must lie in [0,1].');
end
if q == 0
    fraction = 0;
    return
elseif q == 1
    fraction = 0.5;
    return
end

theta = 2*asin(sqrt(q/2));
if theta <= 0.1
    % theta - sin(2*theta)/2, evaluated without cancellation.
    % This branch threshold selects an evaluation formula, not a tolerance.
    term = (2/3)*theta^3;
    area = term;
    for j = 1:11
        term = -term*(4*theta^2)/((2*j+2)*(2*j+3));
        area = area + term;
    end
else
    area = theta - sin(theta)*cos(theta);
end
fraction = area/pi;
end