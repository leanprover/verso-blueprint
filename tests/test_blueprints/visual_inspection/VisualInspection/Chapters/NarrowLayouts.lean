import Verso
import VersoManual
import VersoBlueprint

open Verso.Genre
open Verso.Genre.Manual
open Informal

#doc (Manual) "Narrow Layouts" =>

Blocks from earlier chapters, shown again in half-width cards.

What to check:

* No header chip, badge, or progress bar extends past its card.
* Lean code scrolls inside its card instead of being cut off.
* Compact cards still show which block they belong to.

# Full Cards

:::blueprint_side_by_side +boxed
{blueprint_node "anatomy_metadata"}

{blueprint_node "status_sorry"}
:::

# Busiest Headers

:::blueprint_side_by_side +boxed
{blueprint_node "anatomy_hub"}

{blueprint_node "anatomy_a_deliberately_long_label_that_tests_how_headers_wrap"}
:::

# Statement and Proof

:::blueprint_side_by_side
{blueprint_node "anatomy_theorem" -header +compact}

{blueprint_node "anatomy_theorem" (facet := "proof") (displayLabel := "Proof") -header +compact}
:::
