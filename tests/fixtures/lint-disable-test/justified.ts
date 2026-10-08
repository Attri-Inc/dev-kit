import { legacyApi } from "legacy-package";

// @ts-ignore  // reason: legacy npm typing stub upstream
export const result = legacyApi.run();

// eslint-disable-next-line no-console  // reason: bootstrap log only
console.log("kit booted");
