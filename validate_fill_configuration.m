function enabled = validate_fill_configuration(ratio, mode)
%VALIDATE_FILL_CONFIGURATION Single source of truth for inlet dispatch.
if ~(isnumeric(ratio) && isreal(ratio) && isscalar(ratio) && ...
        isfinite(ratio) && ratio >= 0 && ratio <= 1)
    error('LH2:InvalidTopBottomRatio', ...
        'TopBottomRatio (LH2Model.TF_r) must be a finite real numeric scalar in [0,1].');
end
enabled = ratio > 0;
if enabled && ~(((ischar(mode) && isrow(mode)) || ...
        (isstring(mode) && isscalar(mode))) && any(strcmp(mode, {'spray','jet'})))
    error('LH2:InvalidTopfillMode', ...
        'TopfillMode (LH2Model.TF_mode) must be ''spray'' or ''jet'' when TopBottomRatio > 0.');
end
end
