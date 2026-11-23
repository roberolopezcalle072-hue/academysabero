import bcrypt from 'bcryptjs';

const COST = 10;
// Hash de relleno para que "correo inexistente" tarde lo mismo que "contraseña incorrecta".
const DUMMY = bcrypt.hashSync('relleno-para-igualar-tiempos', COST);

export class PasswordService {
  /** bcrypt solo usa los primeros 72 bytes: más largo se rechaza en vez de truncarse en silencio. */
  static isAcceptable(password: string) {
    return password.length >= 8 && Buffer.byteLength(password, 'utf8') <= 72;
  }

  /** Se guarda con prefijo $2a$ (idéntico algoritmo que $2b$) porque pgcrypto de PostgreSQL solo entiende ese. */
  async hash(password: string) {
    return (await bcrypt.hash(password, COST)).replace(/^\$2b\$/, '$2a$');
  }

  /** Compatible con los hashes que genera pgcrypto (crypt + gen_salt('bf')), como los del restablecimiento por administración. */
  async verify(password: string, hash: string | null) {
    const ok = await bcrypt.compare(password, hash ?? DUMMY);
    return hash !== null && ok;
  }
}
