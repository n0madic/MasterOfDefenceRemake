# 07. Balloon

Available on locations **4, 5, 6** [code: `_floadlocation` → `_fenableballoon(1)`].
Created once (`_fcreateballoon`): `Balloon.b3d` (child `balloon` animates
at speed 0.03), shadow `shadow.b3d` (hidden on location 6), destination marker
`here.b3d`, bomb model `military3.b3d`. Starting position — the center of the
location's rectangle at height `_vballoony = 10` (persisted in the save).
`_funloadlocation` deletes it when leaving locations 3–5 (`_fdeleteballoon`), so every
location starts it at its own centre; `_frestartlocation` keeps it in place.

## Control [code: `_fhandleballoons`, `_fmoveballoonto`]

- RMB on the `road` node → `_fmoveballoonto(x,y,z)`: a tween `_fflux_translate` lasting
  `Round(10·dist)` **ticks** (`_fflux_update(1)` is called once per tick; `dist` is computed from
  XZ coordinates rounded to integers) with cosine easing (ease-in/out,
  `_fflux_tweencosine`); the balloon's height doesn't change. The marker `here.b3d` is shown at the point.
  RMB off the road — message "To move baloon, click on the road."
- Every 2–5 s the balloon randomly rotates in yaw by `Rnd(-360,360)` (decorative).
- The "Go to Balloon" button moves the camera to the balloon.

## Bombs [code: `_fcreatebomb`, `_fhandlebombs`]

- Counter `balloon\timer += 1` per tick. If there's a non-inhabitant enemy within distance < 15 of
  the balloon and `timer > 200` (≈ 3.3 s) — a bomb is dropped, `timer = 0`.
- The bomb appears under the balloon (`MoveEntity(0,1,0)` from the balloon's position) and falls
  at `0.2` units/tick; at `y <= 0` — it explodes (`landExpl` ×1.2, `exp1.wav`):
  every enemy (including inhabitants!) within radius **7**: `life -= 350` (**armor is ignored**),
  `freeze = 30·coldMagic`.
- Damage is fixed at 350; skills don't affect bombs (except Cold Magic).
