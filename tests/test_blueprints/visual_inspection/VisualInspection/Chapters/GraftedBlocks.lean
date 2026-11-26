import Verso
import VersoManual
import VersoBlueprint

open Verso.Genre
open Verso.Genre.Manual
open Informal

#doc (Manual) "Grafted Blocks" =>

Blocks from earlier chapters, shown again with `{blueprint_node}`.

What to check:

* A full graft looks like the block it copies, chips and Lean code included.
* A compact graft without a header still shows which block it belongs to.
* A grafted proof is titled after its statement.

# Full Grafts

{blueprint_node "anatomy_metadata"}

{blueprint_node "anatomy_hub"}

{blueprint_node "anatomy_a_deliberately_long_label_that_tests_how_headers_wrap"}

# Compact Grafts

{blueprint_node "status_sorry" +compact}

{blueprint_node "anatomy_theorem" -header +compact}

# Grafted Proof

{blueprint_node "anatomy_theorem" (facet := "proof")}

{blueprint_node "anatomy_theorem" (facet := "proof") (displayLabel := "Key step") -header +compact}
