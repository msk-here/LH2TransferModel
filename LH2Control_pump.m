function U = LH2Control_pump(P,z,p1,p2)
% Pure regime-specific adapter for a committed controller mode.
assert(z.isPump,'LH2:ControllerMismatch', ...
    'Pump controller received a pressure-driven mode.');
U = LH2ControlEngine('inputs',P,z,p1,p2);
end
