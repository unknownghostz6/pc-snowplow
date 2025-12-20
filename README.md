# pc-snowplow (QBCore)

Snowplowing job for QBCore servers.
This resource is based on the original **pc-snowplow** logic and updated by UnknownGhostz for modern QBCore compatibility while keeping the system lightweight and simple.

---

## What this resource does

* Allows players with the **snowplow** job to plow snow
* Spawns snowplow vehicles for the job
* Displays route checkpoints / markers that must be cleared
* Pays players when plowing work is completed
* Automatically enables vehicle extras on supported plow vehicles
* Fixes the side-plow overlap issue on the large snowplow vehicle

---

## Dependencies

### Required

* **qb-core**

---

## Installation

1. Place the resource in your server:

   ```
   resources/[jobs]/pc-snowplow
   ```

2. Add to `server.cfg`:

   ```
   ensure pc-snowplow
   ```

3. Restart the server or the resource.

---

## Job setup (IMPORTANT)

This script checks for a job named **`snowplow`**.

Open:

```
qb-core/shared/jobs.lua
```

Inside the `QBShared.Jobs = {}` table, add:

```lua
snowplow = { label = 'Snowplow', defaultDuty = true, offDutyPay = false, grades = { ['0'] = { name = 'Plower', payment = 50 } } },
```

Restart `qb-core` or the server after adding the job.

---

## Vehicle setup (IMPORTANT)

Plows used are from the pack located in this link: 

https://www.gta5-mods.com/vehicles/plow-pack-non-els-5m-sp

Your plow vehicles should be added to:

```
qb-core/shared/vehicles.lua
```

Required spawn names:

* `snowatv`
* `18f350plow`
* `snowplow`

Example entries:

```lua
{ model = 'snowplow',        name = 'Snowplow',                      brand = 'SADOT',           price = 100000,  category = 'dot',            type = 'automobile', shop = 'truck' },

  { model = 'snowatv',         name = 'DOT ATV Snow',                  brand = 'SADOT',           price = 100000,  category = 'dot',            type = 'automobile', shop = 'truck' },

{ model = '18f350plow',         name = 'DOT F350',                  brand = 'SADOT',           price = 100000,  category = 'dot',            type = 'automobile', shop = 'truck' },
```

Restart the server after editing.

---

## Vehicle extras behavior

When vehicles are spawned by this script:

### snowatv

* All available extras are enabled automatically.

### snowplow

* All available extras are enabled automatically.
* **Extra 10 is forcibly disabled** to prevent the side-plow overlapping issue found in the snowplow vehicle pack.

This behavior is hardcoded intentionally to avoid visual bugs.

---

## Weather behavior

If your version includes weather logic:

* Snow weather (usually `XMAS`) may be applied
* Blackout behavior may occur depending on plowing progress

Weather features depend on your qb-weathersync configuration.

---

## What this resource does NOT include

* No garage system
* No vehicle key system
* No boss / management menu
* No inventory items for salt
* No equipment wear or repair system

This is intentional to keep the script stable and optimized.

---

## Common issues

### Job won’t start

* Ensure your character job is `snowplow`
* Ensure the job exists in `QBShared.Jobs`

### Vehicles unnamed or look wrong

* Add vehicles to `qb-core/shared/vehicles.lua`

### Side plow overlapping

* Already fixed by disabling Extra 10 on the snowplow

---

## Notes

This script is designed to be:

* Simple
* Optimized
