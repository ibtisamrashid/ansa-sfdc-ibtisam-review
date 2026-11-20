import { readFileSync } from "fs";
import { resolve } from "path";

function permissionSet(name) {
  const xml = readFileSync(
    resolve(
      __dirname,
      "../../../permissionsets",
      `${name}.permissionset-meta.xml`
    ),
    "utf8"
  );
  return new DOMParser().parseFromString(xml, "application/xml");
}

describe("standard portal access to Sequence Hub", () => {
  const hub = permissionSet("ABT_Sequence_Hub_User");
  const portal = permissionSet("ABT_Customer_Portal_User");

  it.each([
    ["classAccesses", "apexClass", "enabled"],
    ["fieldPermissions", "field", "readable"],
    ["objectPermissions", "object", "allowRead"]
  ])(
    "includes the Hub's required %s without an extra assignment",
    (tag, key, grant) => {
      const portalGrants = new Map(
        [...portal.getElementsByTagName(tag)].map((node) => [
          node.getElementsByTagName(key)[0].textContent.trim(),
          node.getElementsByTagName(grant)[0].textContent.trim()
        ])
      );
      for (const node of hub.getElementsByTagName(tag)) {
        const name = node.getElementsByTagName(key)[0].textContent.trim();
        expect({ name, granted: portalGrants.get(name) }).toEqual({
          name,
          granted: "true"
        });
      }
    }
  );
});
