-- Permitir que todos los usuarios autenticados (dueños y cobradores) puedan LEER la configuración
CREATE POLICY "Permitir lectura de configuracion" ON configuracion FOR SELECT TO authenticated USING (true);
