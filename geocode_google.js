import axios from "axios";

/**
 * Places API (New) - Text Search
 * Returns best match: { name, lat, lon, placeId, formattedAddress, source: "google_places" }
 *
 * You MUST set GOOGLE_PLACES_API_KEY in .env
 */
export async function findPlaceGoogle({ shopName, address, area }) {
  const key = process.env.GOOGLE_PLACES_API_KEY;
  if (!key) throw new Error("GOOGLE_PLACES_API_KEY not set in .env");

  const s = String(shopName || "").trim();
  const a = String(address || "").trim();
  const ar = String(area || "").trim();

  // Strongest query is shop + full address
  // If address missing, use area (placeId often is area)
  const textQuery = [s, a || ar, "Malaysia"].filter(Boolean).join(", ");

  const endpoint = "https://places.googleapis.com/v1/places:searchText";

  const resp = await axios.post(
    endpoint,
    {
      textQuery,
      maxResultCount: 5,
      // optional: bias results around Klang Valley-ish
      locationBias: {
        rectangle: {
          low: { latitude: 2.55, longitude: 101.10 },
          high: { latitude: 3.60, longitude: 102.10 },
        },
      },
    },
    {
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": key,
        // Field mask is REQUIRED for Places API (New)
        "X-Goog-FieldMask":
          "places.id,places.displayName,places.formattedAddress,places.location",
      },
      timeout: 15000,
      validateStatus: (s) => s >= 200 && s < 500,
    }
  );

  if (resp.status >= 400) {
    const msg =
      resp.data?.error?.message || `Google Places HTTP ${resp.status}`;
    throw new Error(msg);
  }

  const places = resp.data?.places || [];
  if (!places.length) return null;

  // Best match = first result
  const best = places[0];
  const loc = best.location;

  if (!loc?.latitude || !loc?.longitude) return null;

  const name =
    best.displayName?.text ||
    best.displayName ||
    best.formattedAddress ||
    textQuery;

  return {
    name: `${name} — ${best.formattedAddress || ""}`.trim(),
    lat: Number(loc.latitude),
    lon: Number(loc.longitude),
    placeId: best.id || null,
    formattedAddress: best.formattedAddress || "",
    source: "google_places",
  };
}