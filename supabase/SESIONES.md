# Formación en vivo

Aplica `20261121000600_live_training.sql` después de la migración del campus. El programa dura 30 días y cada clase se imparte en Google Meet. La sesión registra el día del programa, el curso, el horario, el enlace y el estado. El panel maneja los horarios en **America/Lima**. Supabase los conserva como instantes `timestamptz`.

## Administrar una sesión

1. Abre **Administración → Gestionar sesiones en vivo**. Crea una sesión como borrador o publícala como programada con un enlace de Meet.
2. Abre la sesión para cambiar el horario, la descripción o el enlace. Puedes cancelar una sesión en borrador o programada. Deja de mostrarse al alumno y conserva su historial administrativo.
3. Desde la hora de inicio, registra **Presente**, **Ausente** o **Justificada** para cada alumno. El filtro **Solo asistentes** muestra únicamente el estado Presente. Los registros existentes se pueden corregir desde el mismo panel.
4. Después de la hora de fin, marca la sesión como finalizada y, si hay recursos, añade el enlace de la grabación y el del material complementario. El panel del alumno los muestra en **Sesiones anteriores**.

Usa enlaces de archivos y deja el acceso de Drive en **Restringido**. Comparte el archivo con las cuentas de los alumnos que necesiten recuperarlo. SABERO ACADEMY guarda enlaces e identificadores, abre los archivos en Drive y aplica RLS para que solo los alumnos con matrícula activa en el curso puedan obtenerlos. Durante la clase en vivo, el acceso a la llamada se rige además por la configuración de Google Meet.

Las sesiones existentes conservan sus fechas y enlaces. Completa su día y descripción al editarlas. Una sesión programada que ya pasó puede aparecer en el historial, y sus recursos se publican al marcarla como finalizada.

## Verificar

La [prueba de sesiones](tests/live_training.sql) verifica la edición, el horario, el cambio de estado, las restricciones de asistencia manual, el filtro de asistentes y la separación entre cursos. Ejecútala en una base migrada de pruebas con `psql -v ON_ERROR_STOP=1 -f supabase/tests/live_training.sql`. La transacción revierte los datos de prueba. Comprueba el ingreso real a Meet y la reproducción en Drive con cuentas autorizadas del proyecto.
