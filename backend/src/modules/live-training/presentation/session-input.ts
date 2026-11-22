import { BadRequestException } from '@nestjs/common';
import type { SessionDetails } from '../application/live-training';

const limaClock = new Intl.DateTimeFormat('en-US', {
  timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', timeZoneName: 'shortOffset',
});

export function isUuid(value: unknown): value is string {
  return typeof value === 'string' && /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i.test(value);
}

export function sessionDetails(raw: Record<string, unknown>): SessionDetails {
  const title = requiredText(raw.title, 160);
  const description = requiredText(raw.description, 5000);
  const course = raw.course;
  if (!isUuid(course)) throw new BadRequestException();
  const day = Number(raw.day);
  if (typeof raw.day !== 'string' || !/^([1-9]|[12]\d|30)$/.test(raw.day)) throw new BadRequestException();
  const starts = limaInstant(raw.starts);
  const ends = limaInstant(raw.ends);
  if (ends <= starts) throw new BadRequestException();
  const status = raw.status;
  if (status !== 'draft' && status !== 'scheduled' && status !== 'completed') throw new BadRequestException();
  if (status === 'completed' && Date.parse(ends) > Date.now()) throw new BadRequestException();

  const meet = link(raw.meet, ['meet.google.com']);
  if (status === 'scheduled' && !meet) throw new BadRequestException();
  if (meet && !/^\/(?:[a-z]{3}-[a-z]{4}-[a-z]{3}|lookup\/[A-Za-z0-9_-]+)\/?$/.test(new URL(meet).pathname)) {
    throw new BadRequestException();
  }
  return {
    course, title, day, description, starts, ends, meet, status,
    recording: link(raw.recording, ['drive.google.com']),
    material: link(raw.material, ['drive.google.com', 'docs.google.com']),
  };
}

function requiredText(value: unknown, limit: number): string {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > limit) throw new BadRequestException();
  return value.trim();
}

function link(value: unknown, hosts: string[]): string | null {
  if (value === undefined || value === null || value === '') return null;
  const text = requiredText(value, 2048);
  if (!URL.canParse(text) || !/^https:\/\/[^\s]+$/.test(text)) throw new BadRequestException();
  const url = new URL(text);
  if (!hosts.includes(url.hostname) || url.username || url.password || url.port) throw new BadRequestException();
  return text;
}

function limaInstant(value: unknown): string {
  if (typeof value !== 'string' || !/^20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value)) throw new BadRequestException();
  const civil = new Date(`${value}:00Z`);
  if (!Number.isFinite(civil.valueOf()) || civil.toISOString().slice(0, 16) !== value) throw new BadRequestException();
  const offset = limaClock.formatToParts(civil).find(part => part.type === 'timeZoneName')?.value;
  const match = offset?.match(/^GMT([+-])(\d{1,2})(?::(\d{2}))?$/);
  if (!match) throw new BadRequestException();
  const [, sign, hours, minutes = '00'] = match;
  return new Date(`${value}:00${sign}${hours.padStart(2, '0')}:${minutes}`).toISOString();
}
