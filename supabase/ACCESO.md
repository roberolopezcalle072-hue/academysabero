# Acceso privado de SABERO ACADEMY

## Configurar Supabase Auth

1. Aplica las migraciones por orden. Si el Prompt 02 ya está aplicado, ejecuta `20261121000400_private_access.sql`.
2. Configura Google como único proveedor de acceso. Deshabilita Email, teléfono, otros proveedores y sesiones anónimas para este proyecto dedicado. Mantén habilitada la creación de cuentas de Auth para Google, ya que la siguiente regla limita el alta a correos autorizados.
3. En Authentication → Hooks, habilita el hook PostgreSQL **Before User Created** y selecciona `public.academy_before_user_created`. El hook debe estar habilitado antes de abrir el acceso. Solo acepta cuentas nuevas de Google cuyo correo esté activo en la lista.
4. En la configuración de URL de Supabase, registra exactamente `http://localhost:4321/auth/callback` para desarrollo y `https://academy.saberoconsulting.com/auth/callback` para producción. Google Cloud recibe la URI de callback que muestra Supabase. Usa el mismo `SITE_URL` en Astro que en el entorno correspondiente.

[Hook Before User Created](https://supabase.com/docs/guides/auth/auth-hooks/before-user-created-hook) · [Google OAuth en Supabase](https://supabase.com/docs/guides/auth/social-sign-in/auth-google)

### Primer administrador

Un operador de Supabase añade el correo real del administrador a `academy_authorized_emails` desde el SQL Editor o Table Editor. El administrador inicia sesión con Google una vez para crear su identidad en Auth. Todavía no entra al panel y puede recibir una membresía de alumno por la primera comprobación. Para convertir únicamente esa identidad en administrador, usa el UUID verificado en Authentication → Users. Ejecuta como operador en una sola transacción, sustituyendo el parámetro por el UUID real.

```sql
begin;

-- Solo se elimina un perfil inicial que todavía no tiene actividad académica.
delete from public.academy_students
where user_id = '<UUID_DEL_ADMINISTRADOR>';

insert into public.academy_members (user_id, role, active)
values ('<UUID_DEL_ADMINISTRADOR>', 'admin', true)
on conflict (user_id) do update set role = 'admin', active = true;

commit;
```

Si la cuenta ya tiene actividad académica, las claves foráneas protegen su perfil y debe usarse otra identidad administrativa. Los administradores activos acceden por membresía de rol `admin` y sesión de Google verificada. El operador revoca un administrador desactivando su membresía, en lugar de gestionar su correo desde el panel de alumnos.

## Operación diaria

- En `/admin`, autoriza el correo de Google y asócialo con un curso existente. Una asignación directa crea o activa la inscripción al siguiente ingreso. Para exigir un código, selecciona esa opción antes de asociar. El código se muestra una vez y se entrega al destinatario por un canal privado.
- El alumno inicia sesión con Google. Si todavía no tiene una inscripción activa, puede canjear un código asociado a su correo. Un alumno que ya tiene acceso puede canjear otro curso desde el campus.
- La revocación del correo bloquea el acceso en la siguiente solicitud y también en la API de datos de Supabase, incluso con un token previamente emitido. La inscripción y su historial se conservan. La administración puede volver a autorizar el correo.
- El acceso al campus requiere al menos una inscripción con estado `active` y el contenido visible se limita a los cursos cubiertos por esas inscripciones. Las asociaciones no reabren inscripciones canceladas o completadas.

NestJS valida el token con Supabase Auth antes de resolver acceso, canjear códigos o ejecutar operaciones administrativas. Las funciones de base comprueban el correo de Google verificado, una sesión OAuth vigente y los permisos. El navegador recibe cookies HttpOnly con SameSite=Lax y Secure bajo HTTPS. El panel y las rutas de sesión usan `Cache-Control: private, no-store`. El cierre de sesión aplica a la sesión actual. La aplicación utiliza la clave publicable, con las reglas de PostgreSQL aplicadas bajo el token del usuario.

## Verificar

Ejecuta `npm run check` y `npm run build` en ambas aplicaciones. En una base Supabase de pruebas, aplica las migraciones y ejecuta `psql -v ON_ERROR_STOP=1 -f supabase/tests/private_access.sql` con la conexión del operador. Las filas de prueba se revierten. El script cubre admisión del hook, correo rechazado, matrícula directa, canje válido, código erróneo, ajeno y reutilizado, aislamiento por alumno, intento de cambiar roles, revocación y sesión cerrada.

Para verificar Google de extremo a extremo en tu proyecto, inicia sesión desde la interfaz con una cuenta autorizada sin matrícula, canjea su código y abre el campus. Con la sesión todavía abierta, revoca su correo desde otra sesión administrativa y vuelve a cargar el campus. Repite con una cuenta ajena, que debe quedarse en el acceso. Finalmente, cierra sesión desde una cuenta autorizada y confirma que abrir directamente `/campus` redirige a `/ingresar`.
