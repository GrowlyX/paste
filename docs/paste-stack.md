# Paste Stack

The Paste Stack is for moving several things in order, like filling a form
from a document.

1. Press **⇧⌘C** (or the menu bar icon › **Open Paste Stack**). A small stack
   panel docks at the right edge of the screen.
2. Copy things as usual. Each one joins the bottom of the stack.
3. In the destination app, press **⌘V** repeatedly. Each press pastes the next
   item and removes it from the stack.

In the stack panel you can:

- drag rows to reorder them, or reverse the whole stack;
- remove single items;
- **Paste All** at once, joined with new lines.

To add existing cards, drag them from the shelf onto the stack, or right-click
› **Add to Paste Stack**.

Press ⇧⌘C again, or close the panel, to stop collecting.

## Permissions

The stack listens for ⌘V with an event tap, so it needs **Accessibility**
access. While the stack is open, Paste swaps in the next item each time you
press ⌘V, then lets the keystroke through to the app.
