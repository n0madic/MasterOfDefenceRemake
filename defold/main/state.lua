-- State shared between the level script (controller + 3D views) and the HUD gui script
-- (view only): with `script.shared_state` every script type sees the same module.
local M = {}

M.game = nil          -- sim.game instance
M.data = nil          -- sim.data tables
-- What the HUD draws this frame, rebuilt by main/hud_model.lua from the simulation:
-- texts, button states, slider/progress values, messages, popups, skills panel.
M.ui = {}
-- Name of the hovered widget (set by the level script, mirrored by the gui).
M.hover = nil

return M
