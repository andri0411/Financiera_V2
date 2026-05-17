-- Eliminar versiones anteriores para evitar el error de ambigüedad (función sobrecargada)
DROP FUNCTION IF EXISTS public.fn_registrar_no_pago(UUID, UUID);
DROP FUNCTION IF EXISTS public.fn_registrar_no_pago(UUID, UUID, DATE);

-- Actualización de fn_registrar_no_pago para incluir p_fecha_local, extender plazo y marcar cuota como vencida
CREATE OR REPLACE FUNCTION public.fn_registrar_no_pago(
    p_prestamo_id UUID, 
    p_cobrador_id UUID,
    p_fecha_local DATE DEFAULT CURRENT_DATE
) 
RETURNS VOID AS $$
DECLARE
    v_mora_tasa NUMERIC;
    v_prestado NUMERIC;
    v_cuota_diaria NUMERIC;
    v_fecha_fin DATE;
    v_cuota_id UUID;
    v_siguiente_vencimiento DATE;
    v_nueva_fecha_fin DATE;
BEGIN
    -- VALIDACIÓN 1: Si la fecha dada no es día laboral, no se puede penalizar
    IF NOT public.fn_es_dia_laboral(p_fecha_local) THEN
        RETURN; 
    END IF;

    SELECT monto_principal, tasa_mora_aplicada, fecha_finalizacion, cuota_diaria 
    INTO v_prestado, v_mora_tasa, v_fecha_fin, v_cuota_diaria 
    FROM prestamos WHERE id = p_prestamo_id;

    -- Si la tasa de mora en el préstamo es nula, tomamos la de configuración
    IF v_mora_tasa IS NULL THEN
        SELECT porcentaje_mora_diaria INTO v_mora_tasa FROM configuracion WHERE id = 1;
    END IF;

    -- Encontrar la siguiente cuota pendiente
    SELECT id, fecha_vencimiento INTO v_cuota_id, v_siguiente_vencimiento 
    FROM cuotas 
    WHERE prestamo_id = p_prestamo_id AND estado_pago = 'pendiente' 
    ORDER BY fecha_vencimiento ASC LIMIT 1;

    -- Si la próxima cuota vence HOY o ANTES, no tiene adelantos
    IF v_siguiente_vencimiento IS NOT NULL AND v_siguiente_vencimiento <= p_fecha_local THEN
        
        -- 1. Marcar la cuota como vencida
        UPDATE cuotas SET estado_pago = 'vencido' WHERE id = v_cuota_id;

        -- 2. Crear una nueva cuota al final para reponer la que no se pagó
        v_nueva_fecha_fin := public.fn_siguiente_dia_laboral(v_fecha_fin + INTERVAL '1 day');
        
        INSERT INTO cuotas (prestamo_id, numero_cuota, fecha_vencimiento, monto_cuota)
        SELECT 
            p_prestamo_id, 
            COALESCE(MAX(numero_cuota), 0) + 1,
            v_nueva_fecha_fin,
            v_cuota_diaria
        FROM cuotas WHERE prestamo_id = p_prestamo_id;

        -- 3. Actualizar el préstamo: sumar mora, sumar atraso y extender plazo
        UPDATE prestamos 
        SET mora_acumulada = COALESCE(mora_acumulada, 0) + (v_prestado * (COALESCE(v_mora_tasa, 0) / 100)),
            cuotas_atrasadas_conteo = COALESCE(cuotas_atrasadas_conteo, 0) + 1,
            fecha_finalizacion = v_nueva_fecha_fin
        WHERE id = p_prestamo_id;
        
    END IF;

    -- Marcar atención diaria
    INSERT INTO atencion_diaria (cliente_id, cobrador_id, estado, fecha)
    SELECT cliente_id, p_cobrador_id, 'no_pago', p_fecha_local FROM prestamos WHERE id = p_prestamo_id
    ON CONFLICT (cliente_id, fecha) DO UPDATE SET estado = 'no_pago';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
