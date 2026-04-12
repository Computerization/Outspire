import { sendPush, type APNsConfig } from "./apns";

interface Env {
  OUTSPIRE_KV: KVNamespace;
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
  APNS_PRIVATE_KEY: string;
  APNS_BUNDLE_ID: string;
  APNS_AUTH_SECRET: string;
  APNS_USE_SANDBOX: string; // "true" for development builds, unset for production
  GITHUB_CALENDAR_URL: string;
  HOLIDAY_CN_URL: string;
}

// --- Types ---

interface RegisterBody {
  deviceId: string;
  pushStartToken: string;
  pushUpdateToken: string;
  track: "ibdp" | "alevel";
  entryYear: string;
  schedule: Record<string, ClassPeriod[]>; // "1".."5" -> periods
}

interface ClassPeriod {
  start: string; // "08:15"
  end: string; // "08:55"
  name: string;
  room: string;
}

interface StoredRegistration {
  pushStartToken: string;
  pushUpdateToken: string;
  track: "ibdp" | "alevel";
  entryYear: string;
  schedule: Record<string, ClassPeriod[]>;
  paused: boolean;
  resumeDate?: string; // "YYYY-MM-DD"
}

interface HolidayCNDay {
  name: string;
  date: string;
  isOffDay: boolean;
}

interface HolidayCNData {
  year: number;
  days: HolidayCNDay[];
}

interface SchoolCalendar {
  semesters: { start: string; end: string }[];
  specialDays: SpecialDay[];
}

interface SpecialDay {
  date: string;
  type: string;
  name: string;
  cancelsClasses: boolean;
  track: string;
  grades: string[];
  followsWeekday?: number;
}

// A single push job ready to fire
interface PushJob {
  deviceId: string;
  token: string;
  pushType: "liveactivity";
  topic: string;
  payload: Record<string, unknown>;
}

// Stored per time-slot: dispatch:{date}:{HH:MM}
type DispatchSlot = PushJob[];

interface ScheduledPush {
  time: string; // "HH:MM"
  event: "start" | "update" | "end";
  contentState?: Record<string, unknown>;
}

// --- Helpers ---

function todayCST(): string {
  const now = new Date();
  const cst = new Date(now.getTime() + 8 * 60 * 60 * 1000);
  return cst.toISOString().slice(0, 10);
}

function currentTimeCST(): { hours: number; minutes: number } {
  const now = new Date();
  const cst = new Date(now.getTime() + 8 * 60 * 60 * 1000);
  return { hours: cst.getUTCHours(), minutes: cst.getUTCMinutes() };
}

function weekdayCST(): number {
  const now = new Date();
  const cst = new Date(now.getTime() + 8 * 60 * 60 * 1000);
  const day = cst.getUTCDay();
  return day === 0 ? 7 : day;
}

function parseTime(timeStr: string): { h: number; m: number } {
  const [h, m] = timeStr.split(":").map(Number);
  return { h, m };
}

function formatTime(h: number, m: number): string {
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

/**
 * Convert a CST "HH:MM" time string to a Swift-compatible Date value
 * (timeIntervalSinceReferenceDate = seconds since 2001-01-01T00:00:00Z).
 *
 * ActivityKit uses JSONDecoder's default `.deferredToDate` strategy, which
 * expects this format — NOT Unix timestamps.
 */
const APPLE_REFERENCE_DATE = 978307200; // 2001-01-01T00:00:00Z in Unix seconds

function timeToAppleDate(timeStr: string): number {
  const today = todayCST(); // "YYYY-MM-DD"
  const { h, m } = parseTime(timeStr);
  const utcMs = Date.parse(`${today}T${formatTime(h, m)}:00+08:00`);
  return Math.floor(utcMs / 1000) - APPLE_REFERENCE_DATE;
}

function specialDayApplies(
  sd: SpecialDay,
  track: string,
  entryYear: string
): boolean {
  const trackMatch = sd.track === "all" || sd.track === track;
  const gradeMatch =
    sd.grades.includes("all") || sd.grades.includes(entryYear);
  return trackMatch && gradeMatch;
}

function apnsConfig(env: Env): APNsConfig {
  return {
    keyId: env.APNS_KEY_ID,
    teamId: env.APNS_TEAM_ID,
    privateKey: env.APNS_PRIVATE_KEY,
    bundleId: env.APNS_BUNDLE_ID,
    useSandbox: env.APNS_USE_SANDBOX === "true",
  };
}

/** Paginated KV list — follows cursor until all keys are returned. */
async function kvListAll(
  kv: KVNamespace,
  opts: { prefix: string }
): Promise<KVNamespaceListKey<unknown>[]> {
  const allKeys: KVNamespaceListKey<unknown>[] = [];
  let cursor: string | undefined;

  do {
    const res = await kv.list({ prefix: opts.prefix, cursor });
    allKeys.push(...res.keys);
    cursor = res.list_complete ? undefined : (res.cursor as string);
  } while (cursor);

  return allKeys;
}

/** Verify the request carries the shared auth secret. */
function isAuthorized(request: Request, env: Env): boolean {
  const header = request.headers.get("x-auth-secret");
  return header === env.APNS_AUTH_SECRET;
}

// --- Fetch external data (cached in KV) ---

async function fetchHolidayCN(
  env: Env,
  year: string
): Promise<HolidayCNDay[]> {
  const cacheKey = `cache:holiday-cn:${year}`;
  const cached = await env.OUTSPIRE_KV.get(cacheKey, "json");
  if (cached) return cached as HolidayCNDay[];

  const resp = await fetch(`${env.HOLIDAY_CN_URL}/${year}.json`);
  if (!resp.ok) return [];
  const data: HolidayCNData = await resp.json();

  await env.OUTSPIRE_KV.put(cacheKey, JSON.stringify(data.days), {
    expirationTtl: 3600,
  });
  return data.days;
}

async function fetchSchoolCalendarByAcademicYear(
  env: Env,
  academicYear: string // e.g. "2025-2026"
): Promise<SchoolCalendar | null> {
  const cacheKey = `cache:school-cal:${academicYear}`;
  const cached = await env.OUTSPIRE_KV.get(cacheKey, "json");
  if (cached) return cached as SchoolCalendar;

  const resp = await fetch(
    `${env.GITHUB_CALENDAR_URL}/${academicYear}.json`
  );
  if (!resp.ok) return null;
  const data: SchoolCalendar = await resp.json();

  await env.OUTSPIRE_KV.put(cacheKey, JSON.stringify(data), {
    expirationTtl: 300,
  });
  return data;
}

/**
 * Fetch and merge school calendars for the two academic years that could
 * cover the given date. E.g. for 2026-04-12, fetch 2025-2026 and 2026-2027,
 * merge their semesters and specialDays.
 */
async function fetchSchoolCalendar(
  env: Env,
  year: string // natural year, e.g. "2026"
): Promise<SchoolCalendar | null> {
  const y = parseInt(year);
  const [a, b] = await Promise.all([
    fetchSchoolCalendarByAcademicYear(env, `${y - 1}-${y}`),
    fetchSchoolCalendarByAcademicYear(env, `${y}-${y + 1}`),
  ]);

  if (!a && !b) return null;

  return {
    semesters: [...(a?.semesters ?? []), ...(b?.semesters ?? [])],
    specialDays: [...(a?.specialDays ?? []), ...(b?.specialDays ?? [])],
  };
}

// --- Day decision logic ---

interface DayDecision {
  shouldSendPushes: boolean;
  eventName?: string;
  cancelsClasses: boolean;
  useWeekday: number;
}

async function decideTodayForUser(
  env: Env,
  reg: StoredRegistration
): Promise<DayDecision> {
  const today = todayCST();
  const year = today.slice(0, 4);
  const wd = weekdayCST();

  if (reg.paused) {
    if (reg.resumeDate && today >= reg.resumeDate) {
      // Will be auto-resumed by planner
    } else {
      return { shouldSendPushes: false, cancelsClasses: false, useWeekday: wd };
    }
  }

  const cal = await fetchSchoolCalendar(env, year);
  if (cal) {
    const inSemester = cal.semesters.some(
      (s) => today >= s.start && today <= s.end
    );
    if (!inSemester) {
      return { shouldSendPushes: false, cancelsClasses: false, useWeekday: wd };
    }

    const special = cal.specialDays.find(
      (sd) =>
        sd.date === today && specialDayApplies(sd, reg.track, reg.entryYear)
    );
    if (special) {
      if (special.cancelsClasses) {
        return {
          shouldSendPushes: true,
          eventName: special.name,
          cancelsClasses: true,
          useWeekday: wd,
        };
      }
      if (special.type === "makeup" && special.followsWeekday) {
        return {
          shouldSendPushes: true,
          eventName: special.name,
          cancelsClasses: false,
          useWeekday: special.followsWeekday,
        };
      }
    }
  }

  const holidays = await fetchHolidayCN(env, year);
  const holiday = holidays.find((d) => d.date === today);
  if (holiday) {
    if (holiday.isOffDay) {
      return { shouldSendPushes: false, cancelsClasses: false, useWeekday: wd };
    }
    const calMakeup = cal?.specialDays.find(
      (sd) => sd.date === today && sd.type === "makeup"
    );
    const useWd = calMakeup?.followsWeekday ?? 1;
    return { shouldSendPushes: true, cancelsClasses: false, useWeekday: useWd };
  }

  if (wd >= 6) {
    return { shouldSendPushes: false, cancelsClasses: false, useWeekday: wd };
  }

  return { shouldSendPushes: true, cancelsClasses: false, useWeekday: wd };
}

// --- Push schedule builder ---

function buildPushSchedule(
  periods: ClassPeriod[],
  decision: DayDecision
): ScheduledPush[] {
  if (decision.cancelsClasses) {
    // Show the event name briefly, end after 1 hour
    const startTs = timeToAppleDate("07:45");
    const endTs = timeToAppleDate("08:45");
    return [
      {
        time: "07:45",
        event: "start",
        contentState: {
          className: decision.eventName ?? "No Classes",
          roomNumber: "",
          status: "event",
          periodStart: startTs,
          periodEnd: endTs,
          nextClassName: null,
        },
      },
      { time: "08:45", event: "end" },
    ];
  }

  if (periods.length === 0) return [];

  const pushes: ScheduledPush[] = [];

  // Start LA 30 min before first class
  const firstStart = parseTime(periods[0].start);
  const startMinTotal = firstStart.h * 60 + firstStart.m - 30;
  pushes.push({
    time: formatTime(Math.floor(startMinTotal / 60), startMinTotal % 60),
    event: "start",
    contentState: {
      className: periods[0].name,
      roomNumber: periods[0].room,
      status: "upcoming",
      periodStart: timeToAppleDate(periods[0].start),
      periodEnd: timeToAppleDate(periods[0].end),
      nextClassName: periods.length > 1 ? periods[1].name : null,
    },
  });

  for (let i = 0; i < periods.length; i++) {
    const p = periods[i];
    const next = i + 1 < periods.length ? periods[i + 1] : null;

    // Class starts → ongoing
    pushes.push({
      time: p.start,
      event: "update",
      contentState: {
        className: p.name,
        roomNumber: p.room,
        status: "ongoing",
        periodStart: timeToAppleDate(p.start),
        periodEnd: timeToAppleDate(p.end),
        nextClassName: next?.name ?? null,
      },
    });

    // 5 min before end → ending (skip if class is ≤5 min)
    const endTime = parseTime(p.end);
    const startTime = parseTime(p.start);
    const classDuration =
      (endTime.h * 60 + endTime.m) - (startTime.h * 60 + startTime.m);
    if (classDuration > 5) {
      const endingMinTotal = endTime.h * 60 + endTime.m - 5;
      pushes.push({
        time: formatTime(
          Math.floor(endingMinTotal / 60),
          endingMinTotal % 60
        ),
        event: "update",
        contentState: {
          className: p.name,
          roomNumber: p.room,
          status: "ending",
          periodStart: timeToAppleDate(p.start),
          periodEnd: timeToAppleDate(p.end),
          nextClassName: next?.name ?? null,
        },
      });
    }

    // Break/lunch between classes (only if there's a gap)
    if (next && p.end !== next.start) {
      const gapEnd = parseTime(p.end);
      const gapStart = parseTime(next.start);
      const gapMinutes =
        (gapStart.h * 60 + gapStart.m) - (gapEnd.h * 60 + gapEnd.m);
      const breakName = gapMinutes > 30 ? "Lunch Break" : "Break";

      pushes.push({
        time: p.end,
        event: "update",
        contentState: {
          className: breakName,
          roomNumber: "",
          status: "break",
          periodStart: timeToAppleDate(p.end),
          periodEnd: timeToAppleDate(next.start),
          nextClassName: next.name,
        },
      });
    }
    // If p.end === next.start, the "ongoing" push for next class at next.start
    // handles the transition — no break state needed.
  }

  pushes.push({ time: periods[periods.length - 1].end, event: "end" });

  return pushes;
}

// --- Dispatch planning ---

function scheduleToPushJobs(
  deviceId: string,
  reg: StoredRegistration,
  pushSchedule: ScheduledPush[],
  bundleId: string
): Map<string, PushJob[]> {
  const topic = `${bundleId}.push-type.liveactivity`;
  const byTime = new Map<string, PushJob[]>();

  for (const push of pushSchedule) {
    let job: PushJob | null = null;

    if (push.event === "start" && reg.pushStartToken) {
      job = {
        deviceId,
        token: reg.pushStartToken,
        pushType: "liveactivity",
        topic,
        payload: {
          aps: {
            timestamp: 0,
            event: "start",
            "content-state": push.contentState,
            "attributes-type": "ClassActivityAttributes",
            attributes: { startDate: 0 },
          },
        },
      };
    } else if (push.event === "update" && reg.pushUpdateToken) {
      job = {
        deviceId,
        token: reg.pushUpdateToken,
        pushType: "liveactivity",
        topic,
        payload: {
          aps: {
            timestamp: 0,
            event: "update",
            "content-state": push.contentState,
          },
        },
      };
    } else if (push.event === "end" && reg.pushUpdateToken) {
      job = {
        deviceId,
        token: reg.pushUpdateToken,
        pushType: "liveactivity",
        topic,
        payload: {
          aps: {
            timestamp: 0,
            event: "end",
            "dismissal-date": 0,
          },
        },
      };
    }

    if (job) {
      const existing = byTime.get(push.time) ?? [];
      existing.push(job);
      byTime.set(push.time, existing);
    }
  }

  return byTime;
}

/**
 * Daily planner: build dispatch slots for ALL registered devices.
 *
 * Collects all jobs in memory first, then writes each time slot once.
 * This avoids read-merge-write per device per slot (O(N×S) KV ops)
 * and instead does O(N) reads + O(S) writes where S = unique time slots.
 */
async function handleDailyPlan(env: Env): Promise<void> {
  const today = todayCST();

  // 1. Clean up yesterday's dispatch keys
  const yesterday = new Date(Date.now() + 8 * 60 * 60 * 1000);
  yesterday.setUTCDate(yesterday.getUTCDate() - 1);
  const yKey = yesterday.toISOString().slice(0, 10);
  const oldSlots = await kvListAll(env.OUTSPIRE_KV, {
    prefix: `dispatch:${yKey}:`,
  });
  for (const key of oldSlots) {
    await env.OUTSPIRE_KV.delete(key.name);
  }

  // 2. Collect all jobs in memory
  const allJobs = new Map<string, PushJob[]>(); // time -> jobs
  const regKeys = await kvListAll(env.OUTSPIRE_KV, { prefix: "reg:" });

  for (const key of regKeys) {
    const regData = await env.OUTSPIRE_KV.get(key.name, "json");
    if (!regData) continue;

    const reg = regData as StoredRegistration;
    const deviceId = key.name.replace("reg:", "");

    // Auto-resume if needed
    if (reg.paused && reg.resumeDate && today >= reg.resumeDate) {
      reg.paused = false;
      reg.resumeDate = undefined;
      await env.OUTSPIRE_KV.put(key.name, JSON.stringify(reg), {
        expirationTtl: 30 * 24 * 60 * 60,
      });
    }

    const decision = await decideTodayForUser(env, reg);
    if (!decision.shouldSendPushes) continue;

    const wdKey = String(decision.useWeekday);
    const periods = reg.schedule[wdKey] ?? [];
    const pushSchedule = buildPushSchedule(periods, decision);
    const jobsByTime = scheduleToPushJobs(
      deviceId,
      reg,
      pushSchedule,
      env.APNS_BUNDLE_ID
    );

    for (const [time, jobs] of jobsByTime) {
      const existing = allJobs.get(time) ?? [];
      existing.push(...jobs);
      allJobs.set(time, existing);
    }
  }

  // 3. Write all dispatch slots (one KV write per unique time)
  const ttl = 72000; // ~20 hours
  for (const [time, jobs] of allJobs) {
    const slotKey = `dispatch:${today}:${time}`;
    await env.OUTSPIRE_KV.put(slotKey, JSON.stringify(jobs), {
      expirationTtl: ttl,
    });
  }
}

/**
 * Plan a single device's dispatch for today.
 * Used on /register and /resume for immediate scheduling.
 * Only plans future time slots (skips already-passed times).
 */
async function planDeviceForToday(
  env: Env,
  deviceId: string,
  reg: StoredRegistration
): Promise<void> {
  const today = todayCST();
  const decision = await decideTodayForUser(env, reg);

  if (!decision.shouldSendPushes) return;

  const wdKey = String(decision.useWeekday);
  const periods = reg.schedule[wdKey] ?? [];
  const pushSchedule = buildPushSchedule(periods, decision);
  const jobsByTime = scheduleToPushJobs(
    deviceId,
    reg,
    pushSchedule,
    env.APNS_BUNDLE_ID
  );

  const { hours, minutes } = currentTimeCST();
  const nowMinutes = hours * 60 + minutes;
  const ttl = 72000;

  for (const [time, jobs] of jobsByTime) {
    // Skip already-passed time slots
    const t = parseTime(time);
    if (t.h * 60 + t.m < nowMinutes) continue;

    const slotKey = `dispatch:${today}:${time}`;
    const existing =
      ((await env.OUTSPIRE_KV.get(slotKey, "json")) as DispatchSlot) ?? [];

    // Remove any old jobs from this device, then add new ones
    const filtered = existing.filter((j) => j.deviceId !== deviceId);
    filtered.push(...jobs);

    await env.OUTSPIRE_KV.put(slotKey, JSON.stringify(filtered), {
      expirationTtl: ttl,
    });
  }
}

/** Remove a device from all dispatch slots for today. */
async function removeDeviceFromDispatch(
  env: Env,
  deviceId: string
): Promise<void> {
  const today = todayCST();
  const keys = await kvListAll(env.OUTSPIRE_KV, {
    prefix: `dispatch:${today}:`,
  });

  for (const key of keys) {
    const slot =
      ((await env.OUTSPIRE_KV.get(key.name, "json")) as DispatchSlot) ?? [];
    const filtered = slot.filter((j) => j.deviceId !== deviceId);
    if (filtered.length === 0) {
      await env.OUTSPIRE_KV.delete(key.name);
    } else if (filtered.length !== slot.length) {
      await env.OUTSPIRE_KV.put(key.name, JSON.stringify(filtered), {
        expirationTtl: 72000,
      });
    }
  }
}

// --- Per-minute dispatcher ---

async function handleMinuteDispatch(env: Env): Promise<void> {
  const today = todayCST();
  const { hours, minutes } = currentTimeCST();
  const nowTime = formatTime(hours, minutes);

  const slotKey = `dispatch:${today}:${nowTime}`;
  const jobs =
    ((await env.OUTSPIRE_KV.get(slotKey, "json")) as DispatchSlot) ?? [];

  if (jobs.length === 0) return;

  const config = apnsConfig(env);
  const now = Math.floor(Date.now() / 1000);

  for (const job of jobs) {
    // Stamp timestamps at send time
    const aps = (job.payload as any).aps;
    aps.timestamp = now; // APNs protocol field: Unix timestamp
    if (aps.event === "start" && aps.attributes) {
      // startDate is decoded by Swift's Date (timeIntervalSinceReferenceDate)
      aps.attributes.startDate = now - APPLE_REFERENCE_DATE;
    }
    if (aps.event === "end") {
      aps["dismissal-date"] = now + 900; // APNs protocol field: Unix timestamp
    }

    const result = await sendPush(config, {
      token: job.token,
      pushType: job.pushType,
      topic: job.topic,
      payload: job.payload,
    });

    // Log failures for observability; 410 = token revoked
    if (!result.ok) {
      console.error(
        `APNs push failed for device ${job.deviceId}: ${result.status} ${result.body}`
      );
      if (result.status === 410) {
        // Token is permanently invalid — remove registration
        await env.OUTSPIRE_KV.delete(`reg:${job.deviceId}`);
      }
    }
  }

  // Clean up the dispatched slot
  await env.OUTSPIRE_KV.delete(slotKey);
}

// --- HTTP Handlers ---

async function handleRegister(
  request: Request,
  env: Env
): Promise<Response> {
  const body: RegisterBody = await request.json();

  if (!body.deviceId || !body.pushStartToken || !body.schedule) {
    return new Response("Missing required fields", { status: 400 });
  }

  const registration: StoredRegistration = {
    pushStartToken: body.pushStartToken,
    pushUpdateToken: body.pushUpdateToken,
    track: body.track,
    entryYear: body.entryYear,
    schedule: body.schedule,
    paused: false,
  };

  await env.OUTSPIRE_KV.put(
    `reg:${body.deviceId}`,
    JSON.stringify(registration),
    { expirationTtl: 30 * 24 * 60 * 60 }
  );

  // Immediately plan this device's future dispatch slots for today
  await planDeviceForToday(env, body.deviceId, registration);

  return new Response(JSON.stringify({ ok: true }), {
    headers: { "content-type": "application/json" },
  });
}

async function handleUnregister(
  request: Request,
  env: Env
): Promise<Response> {
  const body: { deviceId: string } = await request.json();

  if (!body.deviceId) {
    return new Response("Missing deviceId", { status: 400 });
  }

  await env.OUTSPIRE_KV.delete(`reg:${body.deviceId}`);
  await removeDeviceFromDispatch(env, body.deviceId);

  return new Response(JSON.stringify({ ok: true }), {
    headers: { "content-type": "application/json" },
  });
}

async function handlePause(request: Request, env: Env): Promise<Response> {
  const body: { deviceId: string; resumeDate?: string } =
    await request.json();

  const key = `reg:${body.deviceId}`;
  const existing = await env.OUTSPIRE_KV.get(key, "json");
  if (!existing) return new Response("Not found", { status: 404 });

  const reg = existing as StoredRegistration;
  reg.paused = true;
  reg.resumeDate = body.resumeDate;

  await env.OUTSPIRE_KV.put(key, JSON.stringify(reg), {
    expirationTtl: 30 * 24 * 60 * 60,
  });

  await removeDeviceFromDispatch(env, body.deviceId);

  return new Response(JSON.stringify({ ok: true }), {
    headers: { "content-type": "application/json" },
  });
}

async function handleResume(request: Request, env: Env): Promise<Response> {
  const body: { deviceId: string } = await request.json();

  const key = `reg:${body.deviceId}`;
  const existing = await env.OUTSPIRE_KV.get(key, "json");
  if (!existing) return new Response("Not found", { status: 404 });

  const reg = existing as StoredRegistration;
  reg.paused = false;
  reg.resumeDate = undefined;

  await env.OUTSPIRE_KV.put(key, JSON.stringify(reg), {
    expirationTtl: 30 * 24 * 60 * 60,
  });

  await planDeviceForToday(env, body.deviceId, reg);

  return new Response(JSON.stringify({ ok: true }), {
    headers: { "content-type": "application/json" },
  });
}

// --- Main export ---

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // Health check — no auth required
    if (url.pathname === "/health") {
      return new Response(
        JSON.stringify({ ok: true, date: todayCST() }),
        { headers: { "content-type": "application/json" } }
      );
    }

    // All mutating endpoints require auth
    if (request.method === "POST") {
      if (!isAuthorized(request, env)) {
        return new Response("Unauthorized", { status: 401 });
      }

      switch (url.pathname) {
        case "/register":
          return handleRegister(request, env);
        case "/unregister":
          return handleUnregister(request, env);
        case "/pause":
          return handlePause(request, env);
        case "/resume":
          return handleResume(request, env);
      }
    }

    return new Response("Not Found", { status: 404 });
  },

  async scheduled(
    controller: ScheduledController,
    env: Env,
    ctx: ExecutionContext
  ) {
    if (controller.cron === "30 22 * * *") {
      ctx.waitUntil(handleDailyPlan(env));
    } else {
      ctx.waitUntil(handleMinuteDispatch(env));
    }
  },
} satisfies ExportedHandler<Env>;
