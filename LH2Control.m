function U = LH2Control(P,z,p1,p2)
% Pure regime-specific adapter for a committed controller mode.
assert(~z.isPump,'LH2:ControllerMismatch', ...
    'Pressure-driven controller received a pump mode.');
U = LH2ControlEngine('inputs',P,z,p1,p2);
end
