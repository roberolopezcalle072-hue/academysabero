import {
  BadRequestException, Body, ConflictException, Controller, ForbiddenException, Get, Header, Headers, HttpCode,
  NotFoundException, Param, ParseUUIDPipe, Post, Query, ServiceUnavailableException, UnauthorizedException,
} from '@nestjs/common';
import { ResolveAccess } from '../access/application/resolve-access';
import { bearerToken } from '../access/presentation/bearer-token';
import { SupabaseSchedule } from './supabase-schedule';

const CLASS_TEXT = ['title', 'description', 'objectives', 'content', 'activity', 'outcome'] as const;
const CLASS_LINKS = ['meet_url', 'recording_url', 'material_url', 'class_day'] as const;
const LIMITS: Record<string, number> = {
  title: 160, description: 1000, objectives: 3000, content: 3000, activity: 1000, outcome: 1000,
  meet_url: 2048, recording_url: 2048, material_url: 2048, class_day: 10,
};

@Controller()
export class ScheduleController {
  constructor(private readonly schedule: SupabaseSchedule, private readonly access: ResolveAccess) {}

  /** Cronograma del alumno (o del administrador). Las clases bloqueadas llegan sin contenido ni enlaces. */
  @Get('schedule')
  @Header('Cache-Control', 'private, no-store')
  async get(@Headers('authorization') authorization: string | undefined, @Query('course') course?: string) {
    const { token } = await this.member(authorization);
    if (course !== undefined && !UUID.test(course)) throw new BadRequestException();
    const data = await this.schedule.load(token, course).catch(failure);
    if (!data) throw new NotFoundException();
    return data;
  }

  /** Calendario y turnos que se ofrecen (sin sesión: se ve antes de inscribirse). */
  @Get('schedule/public')
  @Header('Cache-Control', 'public, max-age=30')
  async publicSchedule() {
    const data = await this.schedule.publicSchedule().catch(failure);
    if (!data) throw new NotFoundException();
    return data;
  }

  @Post('schedule/classes/:id/done')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  async done(@Headers('authorization') authorization: string | undefined,
             @Param('id', ParseUUIDPipe) id: string, @Body('done') done: unknown) {
    const { token } = await this.member(authorization);
    if (typeof done !== 'boolean') throw new BadRequestException();
    await this.schedule.setDone(token, id, done).catch(failure);
    return { saved: true };
  }

  @Post('admin/schedule/classes/:id')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  async saveClass(@Headers('authorization') authorization: string | undefined,
                  @Param('id', ParseUUIDPipe) id: string, @Body() body: Record<string, unknown>) {
    const token = await this.admin(authorization);
    const data: Record<string, string> = {};
    for (const key of [...CLASS_TEXT, ...CLASS_LINKS]) {
      if (body?.[key] === undefined) continue;
      const value = body[key];
      if (typeof value !== 'string' || value.length > LIMITS[key]) throw new BadRequestException();
      data[key] = value.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '');
    }
    for (const [key, allowed] of [['access', ['auto', 'enabled', 'blocked']], ['held', ['auto', 'held', 'pending']]] as const) {
      if (body?.[key] === undefined) continue;
      if (typeof body[key] !== 'string' || !allowed.includes(body[key] as never)) throw new BadRequestException();
      data[key] = body[key] as string;
    }
    if (data.title !== undefined && data.title.trim() === '') throw new BadRequestException();
    await this.schedule.saveClass(token, id, data).catch(failure);
    return { saved: true };
  }

  @Post('admin/schedule/settings')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  async saveSettings(@Headers('authorization') authorization: string | undefined, @Body() body: Record<string, unknown>) {
    const token = await this.admin(authorization);
    const course = body?.course;
    const start = body?.startDate === '' || body?.startDate === null || body?.startDate === undefined ? null : body.startDate;
    const time = body?.unlockTime;
    const zone = body?.timezone;
    if (typeof course !== 'string' || !UUID.test(course)) throw new BadRequestException();
    if (start !== null && (typeof start !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(start))) throw new BadRequestException();
    if (typeof time !== 'string' || !/^([01]\d|2[0-3]):[0-5]\d$/.test(time)) throw new BadRequestException();
    if (typeof zone !== 'string' || !/^[A-Za-z_]+(\/[A-Za-z_+\-0-9]+){0,2}$/.test(zone)) throw new BadRequestException();
    const clean = (value: unknown, max: number) => {
      if (value === undefined || value === null || value === '') return null;
      if (typeof value !== 'string' || value.length > max) throw new BadRequestException();
      return value;
    };
    await this.schedule.saveSettings(token, course, start as string | null, time, zone, clean(body.programTitle, 200), clean(body.tagline, 300)).catch(failure);
    return { saved: true };
  }

  @Post('admin/schedule/weeks/:week')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  async saveWeek(@Headers('authorization') authorization: string | undefined,
                 @Param('week') week: string, @Body() body: Record<string, unknown>) {
    const token = await this.admin(authorization);
    const course = body?.course;
    if (typeof course !== 'string' || !UUID.test(course) || !/^\d{1,2}$/.test(week)) throw new BadRequestException();
    const title = typeof body.title === 'string' && body.title.length <= 160 ? body.title : null;
    const objective = typeof body.objective === 'string' && body.objective.length <= 1000 ? body.objective : null;
    const topics = Array.isArray(body.topics) ? body.topics : [];
    if (title === null || objective === null || topics.length > 6) throw new BadRequestException();
    const clean = topics.map((t: unknown) => {
      const item = t as { topic_no?: unknown; title?: unknown };
      if (!Number.isInteger(item?.topic_no) || typeof item?.title !== 'string' || item.title.length > 160) throw new BadRequestException();
      return { topic_no: item.topic_no as number, title: item.title };
    });
    const result = body.result === undefined || body.result === null ? null : body.result;
    if (result !== null && (typeof result !== 'string' || result.length > 1000)) throw new BadRequestException();
    await this.schedule.saveWeek(token, course, Number(week), title, objective, clean, result).catch(failure);
    return { saved: true };
  }

  @Post('admin/schedule/slots/:slot')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  async saveSlot(@Headers('authorization') authorization: string | undefined,
                 @Param('slot') slot: string, @Body() body: Record<string, unknown>) {
    const token = await this.admin(authorization);
    const course = body?.course;
    if (typeof course !== 'string' || !UUID.test(course) || !/^[1-9]$/.test(slot)) throw new BadRequestException();
    const time = (value: unknown) => {
      if (typeof value !== 'string' || !/^([01]\d|2[0-3]):[0-5]\d$/.test(value)) throw new BadRequestException();
      return value;
    };
    const label = typeof body.label === 'string' && body.label.trim() && body.label.length <= 40 ? body.label.trim() : null;
    const capacity = Number(body.capacity);
    const tier = Number(body.tier);
    const meet = body.meet === undefined || body.meet === null ? '' : body.meet;
    if (label === null || typeof meet !== 'string' || meet.length > 2048 ||
        !Number.isInteger(capacity) || capacity < 1 || capacity > 500 || !Number.isInteger(tier) || tier < 1 || tier > 5) {
      throw new BadRequestException();
    }
    await this.schedule.saveSlot(token, course, Number(slot), {
      label, starts: time(body.starts), ends: time(body.ends), meet, capacity, tier, active: body.active === true,
    }).catch(failure);
    return { saved: true };
  }

  @Post('admin/schedule/holidays')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  async setHoliday(@Headers('authorization') authorization: string | undefined, @Body() body: Record<string, unknown>) {
    const token = await this.admin(authorization);
    const { course, day, label } = body ?? {};
    if (typeof course !== 'string' || !UUID.test(course) || typeof day !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(day)) {
      throw new BadRequestException();
    }
    const text = typeof label === 'string' && label.length <= 80 ? label.trim() : '';
    await this.schedule.setHoliday(token, course, day, text, body.remove === true).catch(failure);
    return { saved: true };
  }

  @Get('admin/schedule/students')
  @Header('Cache-Control', 'private, no-store')
  async students(@Headers('authorization') authorization: string | undefined, @Query('course') course?: string) {
    const token = await this.admin(authorization);
    if (!course || !UUID.test(course)) throw new BadRequestException();
    return this.schedule.students(token, course).catch(failure);
  }

  private async member(authorization?: string) {
    const token = bearerToken(authorization);
    const result = await this.access.execute(token).catch(failure);
    if (result.status === 'invalid-session') throw new UnauthorizedException();
    if (result.status !== 'authorized') throw new ForbiddenException();
    return { token, role: result.member.role };
  }

  private async admin(authorization?: string) {
    const { token, role } = await this.member(authorization);
    if (role !== 'admin') throw new ForbiddenException();
    return token;
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function failure(error: unknown): never {
  if (error instanceof ForbiddenException || error instanceof UnauthorizedException || error instanceof NotFoundException) throw error;
  const code = typeof error === 'object' && error !== null && 'code' in error ? (error as { code: string }).code : '';
  if (code === '42501') throw new ForbiddenException();
  if (code === '23503') throw new NotFoundException();
  if (code === '23514' || code === '22001' || code === '22007' || code === '22P02') throw new BadRequestException();
  if (code === '23505') throw new ConflictException();
  throw new ServiceUnavailableException();
}
