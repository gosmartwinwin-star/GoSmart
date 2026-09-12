/* eslint-disable max-len */
import assert from "node:assert/strict";
import {
  readFileSync,
} from "node:fs";
import {
  resolve,
} from "node:path";
import test from "node:test";
import * as ts from "typescript";

const sourcePath =
  resolve(
    process.cwd(),
    "src",
    "index.ts",
  );

const sourceText =
  readFileSync(
    sourcePath,
    "utf8",
  );

const sourceFile =
  ts.createSourceFile(
    sourcePath,
    sourceText,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );

const variableStatement = (
  name: string,
): ts.VariableStatement => {
  for (
    const statement of
    sourceFile.statements
  ) {
    if (
      !ts.isVariableStatement(
        statement,
      )
    ) {
      continue;
    }

    for (
      const declaration of
      statement.declarationList
        .declarations
    ) {
      if (
        ts.isIdentifier(
          declaration.name,
        ) &&
        declaration.name.text ===
          name
      ) {
        return statement;
      }
    }
  }

  throw new Error(
    `Missing declaration: ${name}`,
  );
};

const nearbyModule =
  "./nearby-passenger-discovery-authority.js";

test(
  "index imports nearby passenger discovery authority exactly through value and type imports",
  () => {
    const imports =
      sourceFile.statements
        .filter(
          (
            statement,
          ): statement is ts.ImportDeclaration =>
            ts.isImportDeclaration(
              statement,
            ),
        )
        .filter(
          (statement) =>
            ts.isStringLiteral(
              statement.moduleSpecifier,
            ) &&
            statement.moduleSpecifier
              .text === nearbyModule,
        );

    assert.equal(
      imports.length,
      2,
    );

    const combined =
      imports
        .map(
          (statement) =>
            statement.getText(
              sourceFile,
            ),
        )
        .join("\n");

    assert.match(
      combined,
      /\bdiscoverNearbyPassengerDriversForPassenger\b/,
    );

    assert.match(
      combined,
      /\bNearbyPassengerDiscoveryMeasurementInput\b/,
    );
  },
);

test(
  "nearby compatibility adapter reuses canonical route geometry and existing ride-match deviation measurement",
  () => {
    const text =
      variableStatement(
        "computeNearbyPassengerCompatibility",
      ).getText(sourceFile);

    for (const required of [
      "returnRouteData",
      "encodedPolyline",
      "validateCoordinate",
      "decodeEncodedPolyline",
      "locateRouteAnchors",
      "routeAnchorDirectionCompatible",
      "geoDistanceMeters",
      "RETURN_ROUTE_MATCH_MAX_DETOUR_METERS",
      "computeRideMatchDeviation",
      "pickupRouteIndex",
      "dropoffRouteIndex",
      "pickupDetourMeters",
      "pickupDetourSeconds",
      "dropoffDetourMeters",
      "dropoffDetourSeconds",
    ]) {
      assert.ok(
        text.includes(required),
        `missing compatibility seam: ${required}`,
      );
    }

    assert.equal(
      text.includes(
        "routesClient.computeRoutes",
      ),
      false,
    );

    for (const forbidden of [
      ".set(",
      ".create(",
      ".update(",
      ".delete(",
      ".limit(",
    ]) {
      assert.equal(
        text.includes(forbidden),
        false,
        `forbidden adapter operation: ${forbidden}`,
      );
    }
  },
);

test(
  "nearby callable delegates authenticated empty-DTO authority without client radius or cap",
  () => {
    const text =
      variableStatement(
        "getNearbyPassengerDrivers",
      ).getText(sourceFile);

    for (const required of [
      "region: \"europe-west1\"",
      "timeoutSeconds: 30",
      "memory: \"256MiB\"",
      "minInstances: 0",
      "maxInstances: 3",
      "request.auth?.uid",
      "discoverNearbyPassengerDriversForPassenger",
      "firestore",
      "measureCompatibility",
      "computeNearbyPassengerCompatibility",
      "request.auth.uid",
      "request.data",
    ]) {
      assert.ok(
        text.includes(required),
        `missing callable seam: ${required}`,
      );
    }

    for (const forbidden of [
      "radiusMeters",
      "maxResults",
      ".limit(",
      ".set(",
      ".create(",
      ".update(",
      ".delete(",
      "routesClient.computeRoutes",
    ]) {
      assert.equal(
        text.includes(forbidden),
        false,
        `forbidden callable control: ${forbidden}`,
      );
    }
  },
);

test(
  "nearby callable and compatibility adapter remain unique production declarations",
  () => {
    const countDeclarations = (
      name: string,
    ): number => {
      let count = 0;

      for (
        const statement of
        sourceFile.statements
      ) {
        if (
          !ts.isVariableStatement(
            statement,
          )
        ) {
          continue;
        }

        for (
          const declaration of
          statement.declarationList
            .declarations
        ) {
          if (
            ts.isIdentifier(
              declaration.name,
            ) &&
            declaration.name.text ===
              name
          ) {
            count++;
          }
        }
      }

      return count;
    };

    assert.equal(
      countDeclarations(
        "computeNearbyPassengerCompatibility",
      ),
      1,
    );

    assert.equal(
      countDeclarations(
        "getNearbyPassengerDrivers",
      ),
      1,
    );
  },
);
