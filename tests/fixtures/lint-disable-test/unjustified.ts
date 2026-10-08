// @ts-nocheck

import { someUntypedLib } from "untyped-package";

export function callIt(): unknown {
  // @ts-ignore
  return someUntypedLib.doThing({ x: 1 });
}

// eslint-disable-next-line no-unused-vars
const orphan = 42;
