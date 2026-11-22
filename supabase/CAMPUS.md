# Publicación y campus

Aplica `20261121000500_campus_content.sql` después de las migraciones del modelo y acceso privado. Astro consulta NestJS y NestJS consulta Supabase. El programa público usa la clave publicable con el rol anónimo. El campus y la edición usan el token de sesión y las políticas RLS.

## Publicar la landing

En `/admin/cursos`, abre **Programa de la landing**, completa el título, presentación, descripción, beneficios, duración y datos de inscripción. Marca **Publicar en la landing** para mostrar el contenido. Si corresponde un precio de lanzamiento, indica el importe y su moneda ISO. El botón dirige al enlace HTTPS de inscripción definido por la academia. La admisión al campus sigue sujeta a autorización y matrícula.

El ID del video de bienvenida es opcional. Solo se debe publicar aquí un video que SABERO haya autorizado para visitantes de la landing. Al faltar una publicación, se mantiene visible el acceso de alumnos y se informa que todavía no hay un programa publicado. El sistema parte sin contenido de ejemplo ni precio predeterminado.

## Gestionar un curso

1. Agrega la imagen del curso como un archivo local bajo `frontend/public/images/` y usa su ruta pública bajo `/images/` en el formulario.
2. Crea el curso, sus módulos y las lecciones en **Gestión de cursos**. Selecciona **Publicado** en los tres niveles para que la lección sea visible a los alumnos matriculados. El estado **Archivado** retira el contenido del campus.
3. Registra materiales desde la lección. Usa enlaces a archivos de Google Drive o Docs con un ID de archivo en el segmento `/d/…` o en el parámetro `id`. PostgreSQL guarda el enlace y deriva el identificador. Los enlaces antiguos pueden seguir funcionando y conviene revisar los que carezcan de identificador antes de volver a editarlos.
4. Da acceso al curso desde **Administración de acceso**. La inscripción debe estar activa para leer su contenido. La próxima sesión corresponde a la primera sesión programada de un curso activo cuya hora de fin aún no ha pasado. Las sesiones se gestionan desde el [panel administrativo de formación en vivo](SESIONES.md).

Comparte los recursos privados en Drive con las cuentas de Google de los alumnos autorizados. Conserva el permiso **Restringido** en Drive. Un enlace almacenado en el campus no concede permisos en Google. La plataforma abre el archivo en Drive, sin descargarlo al VPS. La cuenta propietaria de los archivos debe otorgar y revocar los permisos directamente en Drive.

## Avance y consultas

El campus presenta hasta ocho lecciones pendientes, en orden de día y posición. Marcar una lección como completada actualiza el avance del curso. PostgreSQL exige que la lección esté publicada y pertenezca a una inscripción activa del alumno. Desde **Consultas**, el alumno envía mensajes y ve sus respuestas administrativas. Los administradores pueden registrar respuestas en `academy_inquiry_replies`; la interfaz de este módulo presenta el historial al alumno.

La [prueba SQL del campus](tests/campus_content.sql) comprueba publicación, visibilidad por matrícula, materiales, avance y consultas. Ejecútala con `psql -v ON_ERROR_STOP=1 -f supabase/tests/campus_content.sql` en una base de pruebas ya migrada. Sus datos se revierten al terminar. Para verificar reproducción y permisos con archivos reales, usa una cuenta matriculada a la que Drive haya concedido acceso y otra cuenta sin ese permiso.
