-- Exact CAS answers for the website's worked examples.
--
-- The browser demo runs the real toolkit with the numeric mock CAS
-- (testcas.lua), which cannot simplify symbolic expressions. For the four
-- examples on the website these are the results the TI-Nspire CAS works out
-- (− is the negation sign, √( the root, π pi), so the demo shows exact
-- answers. The TI may lay some of them out differently. Keys are the exact
-- strings the solvers send.
local INV = '\239\128\133' -- ^-1, as in tan⁻¹

local R = {}

-- Function graph: f(x) = (x^2-3)/(x-2), x from -6 to 8
local F = '(q9x^2-3)/(q9x-2)'
local D1 = '(q9x^2-4*q9x+3)/(q9x-2)^2'
local WIN = '|q9x≥−6 and q9x≤8'
R['derivative(' .. F .. ',q9x)'] = D1
R['derivative(' .. D1 .. ',q9x)'] = '2/(q9x-2)^3'
for _, inf in ipairs({ '∞', '−∞' }) do
   R['limit(' .. F .. '/q9x,q9x,' .. inf .. ')'] = '1'
   R['limit(' .. F .. '-(1)*q9x,q9x,' .. inf .. ')'] = '2'
end
R['(1)*q9x+(2)'] = 'q9x+2'
R['solve(' .. D1 .. '=0,q9x)' .. WIN] = 'q9x=1 or q9x=3'
R['solve(' .. F .. '=0,q9x)' .. WIN] = 'q9x=−√(3) or q9x=√(3)'
R['(' .. F .. ')|q9x=(0)'] = '3/2'

-- Volume: y = x^2, 0 ≤ y ≤ a, about the y-axis, V = 8π (a = 4)
R['solve(q9y=q9x^2,q9x)'] = 'q9x=−√(q9y) or q9x=√(q9y)'
R['8π'] = '8*π'
R['integral(√(q9y),q9y,0,q9a)|q9a>0'] = '2*q9a^(3/2)/3'
R['integral((√(q9y))^2,q9y,0,q9a)|q9a>0'] = 'q9a^2/2'
R['derivative(√(q9y),q9y)'] = '1/(2*√(q9y))'
R['integral(√(q9y),q9y,0,4)'] = '16/3'
R['integral(π*(√(q9y))^2,q9y,0,4)'] = '8*π'
R['integral(√(1+(1/(2*√(q9y)))^2),q9y,0,4)'] = 'ln(√(17)+4)/4+√(17)'
R['integral(2*π*(√(q9y))*√(1+(1/(2*√(q9y)))^2),q9y,0,4)'] = '(17*√(17)-1)*π/6'

-- Kinematics: a = −(1+v^2), x = 0 and v = 1 when t = 0
local T = 'π/4-tan' .. INV .. '(q9v)'
local X = 'ln(2)/2-ln(q9v^2+1)/2'
R['0+integral(1/(−(1+q8v^2)),q8v,1,q9v)'] = T
R['0+integral(q8v/(−(1+q8v^2)),q8v,1,q9v)'] = X
R['limit(' .. T .. ',q9v,−∞)'] = '3*π/4'
R['(' .. T .. ')|q9v=(0)'] = 'π/4'
R['(' .. X .. ')|q9v=(0)'] = 'ln(2)/2'

return R
