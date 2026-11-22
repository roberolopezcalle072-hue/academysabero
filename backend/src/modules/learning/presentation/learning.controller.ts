import {
  BadRequestException, Body, Controller, ForbiddenException, Get, Header, Headers, HttpCode,
  Inject, NotFoundException, Param, ParseUUIDPipe, Post, Query, ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ResolveAccess } from '../../access/application/resolve-access';
import { bearerToken } from '../../access/presentation/bearer-token';
import type { LearningRepository } from '../application/learning';

export const LEARNING_REPOSITORY = Symbol('LearningRepository');

@Controller()
export class LearningController {
  constructor(
    @Inject(LEARNING_REPOSITORY) private readonly learning: LearningRepository,
    private readonly access: ResolveAccess,
  ) {}

  @Get('program')
  @Header('Cache-Control', 'no-store')
  async program() {
    const program = await this.learning.program().catch(providerError);
    if (!program) throw new NotFoundException();
    return program;
  }

  @Get('campus')
  @Header('Cache-Control', 'private, no-store')
  async home(@Headers('authorization') authorization?: string) {
    const { token } = await this.authorize(authorization);
    return this.learning.home(token).catch(providerError);
  }

  @Get('campus/courses/:courseId')
  @Header('Cache-Control', 'private, no-store')
  async course(@Headers('authorization') authorization: string | undefined, @Param('courseId', ParseUUIDPipe) id: string) {
    const { token } = await this.authorize(authorization);
    const course = await this.learning.course(token, id).catch(providerError);
    if (!course) throw new NotFoundException();
    return course;
  }

  @Post('campus/lessons/:lessonId/complete')
  @HttpCode(200)
  @Header('Cache-Control', 'private, no-store')
  async complete(@Headers('authorization') authorization: string | undefined, @Param('lessonId', ParseUUIDPipe) id: string) {
    const { token } = await this.authorize(authorization, true);
    if (!await this.learning.complete(token, id).catch(providerError)) throw new NotFoundException();
    return { completed: true };
  }

  @Get('campus/inquiries')
  @Header('Cache-Control', 'private, no-store')
  async inquiries(@Headers('authorization') authorization: string | undefined, @Query('page') page = '1') {
    const { token, member } = await this.authorize(authorization, true);
    if (!/^[1-9]\d{0,5}$/.test(page)) throw new BadRequestException();
    return this.learning.inquiries(token, member.id, Number(page)).catch(providerError);
  }

  @Post('campus/inquiries')
  @Header('Cache-Control', 'private, no-store')
  async createInquiry(
    @Headers('authorization') authorization: string | undefined,
    @Body('subject') subject: unknown,
    @Body('body') body: unknown,
  ) {
    const { token, member } = await this.authorize(authorization, true);
    await this.learning.createInquiry(token, member.id, requiredText(subject, 160), requiredText(body, 5000))
      .catch(providerError);
    return { saved: true };
  }

  private async authorize(authorization?: string, studentOnly = false) {
    const token = bearerToken(authorization);
    const result = await this.access.execute(token).catch(providerError);
    if (result.status === 'invalid-session') throw new UnauthorizedException();
    if (result.status !== 'authorized' || (studentOnly && result.member.role !== 'student')) {
      throw new ForbiddenException();
    }
    return { token, member: result.member };
  }
}

function requiredText(value: unknown, limit: number): string {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > limit) throw new BadRequestException();
  return value.trim();
}

function providerError(error: unknown): never {
  if (typeof error === 'object' && error !== null && 'code' in error && error.code === '42501') {
    throw new ForbiddenException();
  }
  throw new ServiceUnavailableException();
}
