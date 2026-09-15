// Diagnostic counters only. Never skip or replace callback tracking/cleanup.
export function createHostCallbackCensus() {
  let active = false;
  const buckets = new Map();
  return {
    reset() { buckets.clear(); active = true; },
    before(entry, arg, liveCount, trackedCount) {
      if (!active) return null;
      const key = JSON.stringify([entry.target, entry.boundary, arg.type?.interfaceTag]);
      let bucket = buckets.get(key);
      if (!bucket) {
        bucket = { target: entry.target, boundary: entry.boundary, tag: arg.type?.interfaceTag,
          arguments: 0, snapshotEntries: 0, maxLiveCallbacks: 0, newlyTracked: 0 };
        buckets.set(key, bucket);
      }
      bucket.arguments++;
      bucket.snapshotEntries += liveCount;
      bucket.maxLiveCallbacks = Math.max(bucket.maxLiveCallbacks, liveCount);
      return { bucket, trackedCount };
    },
    after(observation, trackedCount) {
      if (observation) observation.bucket.newlyTracked += trackedCount - observation.trackedCount;
    },
    finish() {
      active = false;
      return [...buckets.values()].map(bucket => ({ ...bucket }));
    },
  };
}

export function instrumentCallbackCensus(shell) {
  const before = "const callbacksBeforeArgument = new Set(this.runtime.liveCallbacks);";
  const after = "            liftedCallbacks\n          );";
  for (const anchor of [before, after]) {
    if (shell.split(anchor).length !== 2) throw Error("callback census: pinned bridge drift");
  }
  return shell.replace(before,
    "const censusObservation = globalThis.__vbpHostCallbackCensus.before(entry, arg, this.runtime.liveCallbacks.size, liftedCallbacks.size);\n        " + before)
    .replace(after, after + "\n          globalThis.__vbpHostCallbackCensus.after(censusObservation, liftedCallbacks.size);");
}
