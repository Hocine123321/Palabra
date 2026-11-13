// Every cap in one place. Rates are [limit, windowSeconds].
export const LIMITS = {
  bodyBytes: 1_048_576,
  sealedChars: 262_144,
  itemsPerPut: 200,
  listMax: 200,
  listSealedSoft: 900_000,
  itemsTotal: 20_000,
  bytesTotal: 50_000_000, // sealed characters per mirror
  browserDevices: 8,
  rotateBodyBytes: 16_384,
  blobChars: 2048,
  pairTtlSec: 120,
  rates: {
    mirrorsCreate: [5, 3600],
    mirrorsDay: [50, 86400], // all addresses together
    pairStart: [10, 600],
    pairJoin: [20, 600],
    pairPoll: [300, 600],
    itemsPut: [120, 60],
    itemsGet: [240, 60],
    rotate: [6, 3600],
  },
};
