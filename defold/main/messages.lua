-- Message ids and well-known addresses shared by the screens, the screen controller, the
-- audio script and the render script (hashed once).
local M = {}

-- Addresses in the bootstrap collection (the collection proxies' worlds reach them by
-- their socket, `main:`).
M.CONTROLLER = "main:/main#controller"
M.AUDIO = "main:/audio#audio"
M.RENDER = "@render:"

-- Screen controller.
M.SCREEN_READY = hash("screen_ready")          -- a screen finished its init
M.RESTART_LOCATION = hash("restart_location")  -- after a defeat: back to the location's snapshot
M.NEXT_LOCATION = hash("next_location")        -- the location is won: on to the next one
M.QUICK_SAVE = hash("quick_save")              -- write the quick save slot
M.QUICK_LOAD = hash("quick_load")              -- replace the game by the quick save
M.START_GAME = hash("start_game")              -- {mode = new|hard|insane|continue|survival}
M.SHOW_HIGHSCORES = hash("show_highscores")
M.QUIT = hash("quit_game")
M.LEAVE_TO_MENU = hash("leave_to_menu")        -- give up the game: clear its saves, show the menu
M.MAP_CONTINUE = hash("map_continue")          -- the map's "continue": play the location
M.ENDING_DONE = hash("ending_done")            -- the titles / score sheet was left
M.SHOW_MENU = hash("show_menu")

-- (Message payloads stay small -- msg.post caps them at a few KB; the game itself and its
-- saves go through main/session.lua.)

-- Audio. Not `play_sound` etc.: an id the engine registers for its own DDF messages makes
-- msg.post encode the table as that message, dropping our fields.
M.PLAY_SOUND = hash("audio_sound")     -- {name}
M.PLAY_MUSIC = hash("audio_music")     -- {name}
M.PLAY_LOOP = hash("audio_loop")       -- {name}: an ambient loop next to the music
M.STOP_LOOPS = hash("audio_stop_loops")
M.SET_LOOP_GAIN = hash("audio_loop_gain")  -- {name, gain}: a loop heard from afar
M.SET_VOLUMES = hash("audio_volumes")  -- {music, sound} in 0..1

-- Render script.
M.SET_SCENE = hash("set_scene")      -- {clear_color, light_dir, light_color, ambient, point_light<i>, point_color<i>}
M.SET_DISPLAY = hash("set_display")  -- {wide, gamma}

-- Engine messages.
M.PROXY_LOADED = hash("proxy_loaded")
M.PROXY_UNLOADED = hash("proxy_unloaded")

return M
