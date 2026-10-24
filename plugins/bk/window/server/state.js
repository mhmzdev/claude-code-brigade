// The kitchen's state, as the Window shows it. One plain object, a few reducers,
// and a listener list. Sources (demo or live) call the reducers; the server
// broadcasts a snapshot after each change (throttled) and discrete events as they happen.

export const HELPER_KINDS = ['commis', 'taster', 'inspector', 'runner'];
export const ACTIVITIES = ['idle', 'thinking', 'editing', 'running', 'reading', 'waiting', 'offline'];

export function createState(kitchen) {
  const state = {
    kitchen: { repo: 'kitchen', root: '', mode: 'clone', trunk: 'main', ...kitchen },
    sous: actor('sous', 'Sous Chef'),
    headChef: { pending: [] },          // questions waiting on the human
    stations: [],                       // [{ id, name, branch, dirty, ahead, ticket, cook }]
    helpers: [],                        // transient sub-agents in flight
    rail: { backlog: [], todo: [], 'in-progress': [], rfr: [], done: [] },
    log: [],                            // last messages between sessions
    record: { total: 0, kinds: {} },    // what the kitchen remembers: pages per docs kind
    updatedAt: Date.now(),
  };
  const listeners = new Set();
  let pending = null;

  function actor(id, name) {
    return { id, name, session: null, status: 'offline', activity: 'offline', model: null, since: Date.now(), bubble: null, startedAt: null, handoffAt: null }; // startedAt: this conversation began; handoffAt: the last handoff written
  }

  function emit(type, payload) {
    for (const fn of listeners) fn({ type, ...payload });
  }

  // Snapshots coalesce: many reducer calls in one tick → one broadcast.
  function touch() {
    state.updatedAt = Date.now();
    if (pending) return;
    pending = setTimeout(() => { pending = null; emit('snapshot', { state }); }, 50);
  }

  const api = {
    state,
    subscribe(fn) { listeners.add(fn); return () => listeners.delete(fn); },
    snapshot() { return state; },

    setKitchen(patch) { Object.assign(state.kitchen, patch); touch(); },
    setRecord(r) { state.record = { total: r.total || 0, kinds: r.kinds || {} }; touch(); },

    upsertStation(id, patch) {
      let s = state.stations.find((x) => x.id === id);
      if (!s) {
        s = { id, name: id, branch: null, dirty: false, ahead: 0, ticket: null, cook: actor(id, `Cook ${id.replace(/\D+/g, '')}`) };
        state.stations.push(s);
        state.stations.sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
      }
      const { cook, ...rest } = patch;
      Object.assign(s, rest);
      if (cook) Object.assign(s.cook, cook);
      touch();
      return s;
    },
    removeStation(id) {
      state.stations = state.stations.filter((s) => s.id !== id); touch();
    },

    // who: 'sous' or a station id
    setActor(who, patch) {
      const a = who === 'sous' ? state.sous : state.stations.find((s) => s.id === who)?.cook;
      if (!a) return;
      for (const k of Object.keys(patch)) if (patch[k] === undefined) delete patch[k];
      if (patch.activity && patch.activity !== a.activity) a.since = Date.now();
      Object.assign(a, patch);
      touch();
    },

    say(who, text, ttl = 6000) {
      api.setActor(who, { bubble: { text: String(text).slice(0, 120), until: Date.now() + ttl } });
      emit('bubble', { who, text });
    },

    message({ from, to, kind, text = '' }) {
      const entry = { t: Date.now(), from, to, kind, text: String(text).slice(0, 400) };
      state.log.push(entry);
      if (state.log.length > 200) state.log.splice(0, state.log.length - 200);
      emit('message', entry);
      touch();
      return entry;
    },

    helperStart({ id, kind, from, note = '' }) {
      const h = { id, kind, from, note, since: Date.now() };
      state.helpers.push(h);
      emit('helper:start', h);
      touch();
      return h;
    },
    helperEnd(id, verdict = '') {
      const i = state.helpers.findIndex((h) => h.id === id);
      if (i < 0) return;
      const [h] = state.helpers.splice(i, 1);
      emit('helper:end', { ...h, verdict });
      touch();
    },

    ask({ id, from, text, options = [] }) {
      if (!state.headChef.pending.find((q) => q.id === id)) {
        state.headChef.pending.push({ id, from, text, options, since: Date.now() });
        emit('ask', { id, from, text });
        touch();
      }
    },
    answer(id) {
      state.headChef.pending = state.headChef.pending.filter((q) => q.id !== id);
      emit('answered', { id });
      touch();
    },

    setRail(rail) { state.rail = { backlog: [], todo: [], 'in-progress': [], rfr: [], done: [], ...rail }; touch(); },
    moveTicket(id, column, patch = {}) {
      let t = null;
      for (const col of Object.keys(state.rail)) {
        const i = state.rail[col].findIndex((x) => x.id === id);
        if (i >= 0) { [t] = state.rail[col].splice(i, 1); break; }
      }
      t = { ...(t || { id, title: id }), ...patch, status: column };
      (state.rail[column] ||= []).push(t);
      emit('ticket', { id, column });
      touch();
    },

    event(type, payload) { emit(type, payload); },
  };
  return api;
}
