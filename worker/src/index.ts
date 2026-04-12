import { sendPush, type APNsConfig } from "./apns";

interface Env {
  OUTSPIRE_KV: KVNamespace;
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
  APNS_PRIVATE_KEY: string;
  APNS_BUNDLE_ID: string;
  APNS_AUTH_SECRET: string;
  GITHUB_CALENDAR_URL: string;
  HOLIDAY_CN_URL: string;
}

// --- Types ---

interface RegisterBody {
  deviceId: string;
  pushStartToken: string;
  sandbox?: boolean;
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
  sandbox: boolean;
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
  sandbox: boolean;
  pushType: "liveactivity";
  topic: string;
  payload: Record<string, unknown>;
}

// Stored per time-slot: dispatch:{date}:{HH:MM}
type DispatchSlot = PushJob[];

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
 */
const APPLE_REFERENCE_DATE = 978307200;

function timeToAppleDate(timeStr: string): number {
  const today = todayCST();
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
  academicYear: string
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

async function fetchSchoolCalendar(
  env: Env,
  year: string
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

// --- Build start push payload ---
// Shared between daily planner and mid-day /register handler.

function buildStartPushJob(
  deviceId: string,
  reg: StoredRegistration,
  periods: ClassPeriod[],
  decision: DayDecision,
  bundleId: string
): { time: string; job: PushJob } | null {
  const topic = `${bundleId}.push-type.liveactivity`;
  const now = Math.floor(Date.now() / 1000);

  if (decision.cancelsClasses) {
    return {
      time: "07:45",
      job: {
        deviceId,
        token: reg.pushStartToken,
        sandbox: reg.sandbox,
        pushType: "liveactivity",
        topic,
        payload: {
          aps: {
            timestamp: now,
            event: "start",
            "content-state": {
              classes: [
                {
                  name: decision.eventName ?? "No Classes",
                  room: "",
                  start: timeToAppleDate("07:45"),
                  end: timeToAppleDate("08:45"),
                },
              ],
            },
            // Stale 1h after the event push (07:45 + 1h = 08:45 CST)
            "stale-date": Math.floor(
              Date.parse(`${todayCST()}T08:45:00+08:00`) / 1000
            ),
            alert: {
              title: decision.eventName ?? "No Classes",
              body: "Classes are cancelled today",
            },
            "attributes-type": "ClassActivityAttributes",
            attributes: {
              startDate: now - APPLE_REFERENCE_DATE,
            },
          },
        },
      },
    };
  }

  if (periods.length === 0) return null;

  // Build content-state with all classes
  const classes = periods.map((p) => ({
    name: p.name,
    room: p.room,
    start: timeToAppleDate(p.start),
    end: timeToAppleDate(p.end),
  }));

  // Stale date = 15 min after last class
  const lastEnd = parseTime(periods[periods.length - 1].end);
  const staleDateUnix =
    Math.floor(
      Date.parse(
        `${todayCST()}T${formatTime(lastEnd.h, lastEnd.m)}:00+08:00`
      ) / 1000
    ) + 900;

  return {
    time: "08:00", // Start at first bell
    job: {
      deviceId,
      token: reg.pushStartToken,
      sandbox: reg.sandbox,
      pushType: "liveactivity",
      topic,
      payload: {
        aps: {
          timestamp: now,
          event: "start",
          "content-state": { classes },
          "stale-date": staleDateUnix,
          alert: {
            title: "Today's Schedule",
            body: `${periods.length} classes today`,
          },
          "attributes-type": "ClassActivityAttributes",
          attributes: {
            startDate: now - APPLE_REFERENCE_DATE,
          },
        },
      },
    },
  };
}

// --- Daily planner: runs once early morning (CST ~06:30) ---

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

  // Also clean up pushed-today markers from yesterday
  const oldPushed = await kvListAll(env.OUTSPIRE_KV, {
    prefix: `pushed:${yKey}:`,
  });
  for (const key of oldPushed) {
    await env.OUTSPIRE_KV.delete(key.name);
  }

  // 2. Collect all jobs in memory (one per user, all at same time "08:00")
  const allJobs = new Map<string, PushJob[]>();
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
    const result = buildStartPushJob(
      deviceId,
      reg,
      periods,
      decision,
      env.APNS_BUNDLE_ID
    );
    if (!result) continue;

    const existing = allJobs.get(result.time) ?? [];
    existing.push(result.job);
    allJobs.set(result.time, existing);
  }

  // 3. Write dispatch slots (typically just one at "08:00")
  const ttl = 72000;
  for (const [time, jobs] of allJobs) {
    const slotKey = `dispatch:${today}:${time}`;
    await env.OUTSPIRE_KV.put(slotKey, JSON.stringify(jobs), {
      expirationTtl: ttl,
    });
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

  // Send all pushes concurrently (batched, max 20)
  const BATCH_SIZE = 20;
  for (let i = 0; i < jobs.length; i += BATCH_SIZE) {
    const batch = jobs.slice(i, i + BATCH_SIZE);

    const results = await Promise.all(
      batch.map((job) => {
        const jobConfig = { ...config, useSandbox: job.sandbox };
        return sendPush(jobConfig, {
          token: job.token,
          pushType: job.pushType,
          topic: job.topic,
          payload: job.payload,
        }).then((result) => ({ job, result }));
      })
    );

    for (const { job, result } of results) {
      if (result.ok) {
        // Mark as pushed today to prevent duplicate from /register
        await env.OUTSPIRE_KV.put(
          `pushed:${today}:${job.deviceId}`,
          "1",
          { expirationTtl: 72000 }
        );
      } else {
        console.error(
          `APNs push failed for device ${job.deviceId}: ${result.status} ${result.body}`
        );
        if (result.status === 410) {
          await env.OUTSPIRE_KV.delete(`reg:${job.deviceId}`);
        }
      }
    }
  }

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
    sandbox: body.sandbox ?? false,
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

  const today = todayCST();

  // Check if already pushed today (idempotency)
  const alreadyPushed = await env.OUTSPIRE_KV.get(
    `pushed:${today}:${body.deviceId}`
  );
  if (alreadyPushed) {
    return new Response(
      JSON.stringify({ ok: true, pushed: false, reason: "already_pushed_today" }),
      { headers: { "content-type": "application/json" } }
    );
  }

  // If the daily dispatch slot hasn't fired yet, plan into it
  const decision = await decideTodayForUser(env, registration);
  if (!decision.shouldSendPushes) {
    return new Response(
      JSON.stringify({ ok: true, pushed: false, reason: "no_classes_today" }),
      { headers: { "content-type": "application/json" } }
    );
  }

  const wdKey = String(decision.useWeekday);
  const periods = registration.schedule[wdKey] ?? [];

  // Filter to remaining classes only (for mid-day registration)
  const { hours, minutes } = currentTimeCST();
  const nowMinutes = hours * 60 + minutes;
  const remainingPeriods = periods.filter((p) => {
    const end = parseTime(p.end);
    return end.h * 60 + end.m > nowMinutes;
  });

  if (remainingPeriods.length === 0) {
    return new Response(
      JSON.stringify({ ok: true, pushed: false, reason: "no_remaining_classes" }),
      { headers: { "content-type": "application/json" } }
    );
  }

  const result = buildStartPushJob(
    body.deviceId,
    registration,
    remainingPeriods,
    decision,
    env.APNS_BUNDLE_ID
  );

  if (!result) {
    return new Response(
      JSON.stringify({ ok: true, pushed: false }),
      { headers: { "content-type": "application/json" } }
    );
  }

  // Check if dispatch slot is in the future — add to it
  const slotTime = parseTime(result.time);
  if (slotTime.h * 60 + slotTime.m > nowMinutes) {
    // Slot hasn't fired yet — merge into dispatch slot
    const slotKey = `dispatch:${today}:${result.time}`;
    const existing =
      ((await env.OUTSPIRE_KV.get(slotKey, "json")) as DispatchSlot) ?? [];
    const filtered = existing.filter((j) => j.deviceId !== body.deviceId);
    filtered.push(result.job);
    await env.OUTSPIRE_KV.put(slotKey, JSON.stringify(filtered), {
      expirationTtl: 72000,
    });
    return new Response(
      JSON.stringify({ ok: true, pushed: false, reason: "scheduled" }),
      { headers: { "content-type": "application/json" } }
    );
  }

  // Slot already passed — send immediately
  const config = apnsConfig(env);
  const jobConfig = { ...config, useSandbox: registration.sandbox };
  const pushResult = await sendPush(jobConfig, {
    token: result.job.token,
    pushType: result.job.pushType,
    topic: result.job.topic,
    payload: result.job.payload,
  });

  if (pushResult.ok) {
    await env.OUTSPIRE_KV.put(
      `pushed:${today}:${body.deviceId}`,
      "1",
      { expirationTtl: 72000 }
    );
  } else {
    console.error(
      `APNs push failed for device ${body.deviceId}: ${pushResult.status} ${pushResult.body}`
    );
  }

  return new Response(
    JSON.stringify({ ok: true, pushed: pushResult.ok }),
    { headers: { "content-type": "application/json" } }
  );
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

  // Clean dispatch slots containing this device
  const today = todayCST();
  const keys = await kvListAll(env.OUTSPIRE_KV, {
    prefix: `dispatch:${today}:`,
  });
  for (const key of keys) {
    const slot =
      ((await env.OUTSPIRE_KV.get(key.name, "json")) as DispatchSlot) ?? [];
    const filtered = slot.filter((j) => j.deviceId !== body.deviceId);
    if (filtered.length === 0) {
      await env.OUTSPIRE_KV.delete(key.name);
    } else if (filtered.length !== slot.length) {
      await env.OUTSPIRE_KV.put(key.name, JSON.stringify(filtered), {
        expirationTtl: 72000,
      });
    }
  }

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

  // Re-trigger scheduling — same logic as mid-day /register
  const today = todayCST();
  const alreadyPushed = await env.OUTSPIRE_KV.get(
    `pushed:${today}:${body.deviceId}`
  );
  if (alreadyPushed) {
    return new Response(
      JSON.stringify({ ok: true, pushed: false, reason: "already_pushed_today" }),
      { headers: { "content-type": "application/json" } }
    );
  }

  const decision = await decideTodayForUser(env, reg);
  if (!decision.shouldSendPushes) {
    return new Response(
      JSON.stringify({ ok: true, pushed: false }),
      { headers: { "content-type": "application/json" } }
    );
  }

  const wdKey = String(decision.useWeekday);
  const periods = reg.schedule[wdKey] ?? [];
  const { hours, minutes } = currentTimeCST();
  const nowMinutes = hours * 60 + minutes;
  const remainingPeriods = periods.filter((p) => {
    const end = parseTime(p.end);
    return end.h * 60 + end.m > nowMinutes;
  });

  if (remainingPeriods.length === 0) {
    return new Response(
      JSON.stringify({ ok: true, pushed: false }),
      { headers: { "content-type": "application/json" } }
    );
  }

  const result = buildStartPushJob(
    body.deviceId,
    reg,
    remainingPeriods,
    decision,
    env.APNS_BUNDLE_ID
  );

  if (!result) {
    return new Response(
      JSON.stringify({ ok: true, pushed: false }),
      { headers: { "content-type": "application/json" } }
    );
  }

  // Send immediately (resume is always mid-day)
  const config = apnsConfig(env);
  const jobConfig = { ...config, useSandbox: reg.sandbox };
  const pushResult = await sendPush(jobConfig, {
    token: result.job.token,
    pushType: result.job.pushType,
    topic: result.job.topic,
    payload: result.job.payload,
  });

  if (pushResult.ok) {
    await env.OUTSPIRE_KV.put(
      `pushed:${today}:${body.deviceId}`,
      "1",
      { expirationTtl: 72000 }
    );
  }

  return new Response(
    JSON.stringify({ ok: true, pushed: pushResult.ok }),
    { headers: { "content-type": "application/json" } }
  );
}

// --- Main export ---

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return new Response(
        JSON.stringify({ ok: true, date: todayCST() }),
        { headers: { "content-type": "application/json" } }
      );
    }

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
