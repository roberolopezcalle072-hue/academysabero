import {
  BadRequestException, Body, ConflictException, Controller, ForbiddenException, Get, Header, Headers,
  Inject, NotFoundException, Param, Post, Query, ServiceUnavailableException, UnauthorizedException,
} from '@nestjs/common';
import { ResolveAccess } from '../../access/application/resolve-access';
import { bearerToken } from '../../access/presentation/bearer-token';
import { editorialTables, type EditorialEntity, type EditorialRepository } from '../application/editorial';
import { parseEditorial, validId } from './editorial-fields';

export const EDITORIAL_REPOSITORY = Symbol('EditorialRepository');

@Controller('admin/learning')
export class EditorialController {
  constructor(
    @Inject(EDITORIAL_REPOSITORY) private readonly editorial: EditorialRepository,
    private readonly access: ResolveAccess,
  ) {}

  @Get()
  @Header('Cache-Control', 'private, no-store')
  async catalog(
    @Headers('authorization') authorization: string | undefined, @Query('page') page = '1',
    @Query('course') course?: string,
  ) {
    const token = await this.authorize(authorization);
    if (!/^[1-9]\d{0,5}$/.test(page) || (course !== undefined && (typeof course !== 'string' || !validId(course)))) {
      throw new BadRequestException();
    }
    return this.editorial.catalog(token, Number(page), course).catch(providerError);
  }

  @Post(':entity')
  @Header('Cache-Control', 'private, no-store')
  async save(@Headers('authorization') authorization: string | undefined, @Param('entity') entity: string, @Body() raw: unknown) {
    const token = await this.authorize(authorization);
    if (!Object.hasOwn(editorialTables, entity) || !raw || typeof raw !== 'object' || Array.isArray(raw)) {
      throw new BadRequestException();
    }
    const content = raw as Record<string, unknown>;
    const id = content.id || null;
    if (id !== null && (typeof id !== 'string' || !validId(id) || entity === 'program')) throw new BadRequestException();
    const type = entity as EditorialEntity;
    const data = parseEditorial(type, content, id !== null);
    if (!await this.editorial.save(token, type, data, id).catch(providerError)) throw new NotFoundException();
    return { saved: true };
  }

  private async authorize(authorization?: string) {
    const token = bearerToken(authorization);
    const result = await this.access.execute(token).catch(providerError);
    if (result.status === 'invalid-session') throw new UnauthorizedException();
    if (result.status !== 'authorized' || result.member.role !== 'admin') throw new ForbiddenException();
    return token;
  }
}

function providerError(error: unknown): never {
  const code = typeof error === 'object' && error !== null && 'code' in error ? error.code : null;
  if (code === '42501') throw new ForbiddenException();
  if (code === '23505' || code === '23503' || code === '23514') throw new ConflictException();
  throw new ServiceUnavailableException();
}
