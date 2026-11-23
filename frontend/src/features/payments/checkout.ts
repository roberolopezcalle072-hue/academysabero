// Código que corre en el NAVEGADOR. Es el único lugar de la web que conoce cada pasarela.
// Para añadir otra pasarela: escribir una función `open<Nombre>` y registrarla en `openers`.

export interface StartedPayment {
  paymentId: string;
  provider: string;
  config: Record<string, unknown>;
  amount: number;
  amountMinor: number;
  currency: string;
  title: string;
  email: string;
}

/** Abre el formulario de pago de la pasarela y entrega el token cuando el cliente lo completa. */
type Opener = (
  payment: StartedPayment,
  handlers: { onToken: (token: string, extra?: Record<string, unknown>) => Promise<void>; onError: (message: string) => void; onClose: () => void },
) => Promise<void>;

/** Resultado de la verificación 3D Secure del banco (lo envía tal cual al servidor). */
export type Parameters3DS = Record<string, unknown>;

function loadScript(src: string): Promise<void> {
  return new Promise((resolve, reject) => {
    if (document.querySelector(`script[src="${src}"]`)) return resolve();
    const script = document.createElement('script');
    script.src = src;
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error('No se pudo cargar el formulario de pago.'));
    document.head.appendChild(script);
  });
}

// ---- Culqi Checkout v3 (global Culqi + callback culqi()): entrega un token que el backend convierte en cargo ----
const openCulqi: Opener = async (payment, { onToken, onError, onClose }) => {
  await loadScript('https://checkout.culqi.com/js/v3');
  const w = window as unknown as Record<string, any>;
  const Culqi = w.Culqi;
  // Huella del dispositivo para el antifraude y el 3D Secure (si no carga, el cobro sigue sin ella).
  let deviceId: string | undefined;
  try {
    await loadScript('https://3ds.culqi.com');
    deviceId = await w.Culqi3DS?.generateDevice?.();
  } catch { deviceId = undefined; }
  Culqi.publicKey = String(payment.config.publicKey ?? '');
  Culqi.settings({ title: 'SABERO Academy', currency: payment.currency, description: payment.title, amount: payment.amountMinor });
  Culqi.options({
    lang: 'es', installments: false, modal: true,
    paymentMethods: { tarjeta: true, yape: true, billetera: false, bancaMovil: false, agente: false, cuotealo: false },
  });
  w.culqi = async () => {
    if (Culqi.token) {
      Culqi.close();
      await onToken(String(Culqi.token.id), deviceId ? { deviceId } : undefined);
    } else if (Culqi.error) {
      Culqi.close();
      onError(String(Culqi.error.user_message || 'No se pudo procesar el pago.'));
    }
  };
  Culqi.open();
  // El cliente cierra el formulario sin pagar.
  const timer = window.setInterval(() => {
    if (!document.querySelector('iframe[src*="culqi"]')) { window.clearInterval(timer); onClose(); }
  }, 800);
};

// ---- Simulador: solo existe cuando el backend usa PAYMENT_PROVIDER=mock (desarrollo) ----
const openMock: Opener = async (_payment, { onToken, onClose }) => {
  if (window.confirm('Simulador de pago (solo desarrollo).\n\nAceptar = pago aprobado · Cancelar = pago rechazado')) {
    await onToken(localStorage.getItem('mock3ds') === '1' ? 'tok_mock_3ds' : 'tok_mock_ok');
  } else {
    await onToken('tok_mock_bad');
  }
  onClose();
};

const openers: Record<string, Opener> = { culqi: openCulqi, mock: openMock };

// ---- 3D Secure: el banco pide verificar al titular (clave, app del banco, etc.) ----
type Authenticator = (payment: StartedPayment, token: string) => Promise<Parameters3DS>;

const authenticateCulqi: Authenticator = async (payment, token) => {
  await loadScript('https://3ds.culqi.com');
  const C3 = (window as unknown as Record<string, any>).Culqi3DS;
  if (!C3) throw new Error('No se pudo cargar la verificación de tu banco.');
  C3.publicKey = String(payment.config.publicKey ?? '');
  // Se configura de nuevo en cada cobro.
  C3.settings = {
    charge: { totalAmount: payment.amountMinor, currency: payment.currency, returnUrl: location.href.split('#')[0] },
    card: { email: payment.email },
  };
  C3.options = { showModal: true, showLoading: true, showIcon: true };

  return new Promise<Parameters3DS>((resolve, reject) => {
    const finish = () => { window.removeEventListener('message', onMessage); window.clearTimeout(timer); try { C3.reset?.(); } catch { /* nada */ } };
    const onMessage = (event: MessageEvent) => {
      if (event.origin !== window.location.origin) return;
      const { parameters3DS, error } = (event.data ?? {}) as { parameters3DS?: Parameters3DS; error?: string };
      if (parameters3DS) { finish(); resolve(parameters3DS); }
      else if (error) { finish(); reject(new Error(String(error))); }
    };
    const timer = window.setTimeout(() => { finish(); reject(new Error('La verificación de tu banco tardó demasiado. Inténtalo de nuevo.')); }, 5 * 60 * 1000);
    window.addEventListener('message', onMessage);
    Promise.resolve(C3.initAuthentication(token)).catch((e: unknown) => { finish(); reject(e instanceof Error ? e : new Error('No se pudo iniciar la verificación de tu banco.')); });
  });
};

// Simulador (solo desarrollo): responde de inmediato con datos de ejemplo.
const authenticateMock: Authenticator = async () => (
  { eci: '05', xid: 'bW9ja194aWQ=', cavv: 'bW9ja19jYXZ2', protocolVersion: '2.1.0', directoryServerTransactionId: '755f8c81-a4db-4c84-8b8c-23f6b0196cfd' }
);

const authenticators: Record<string, Authenticator> = { culqi: authenticateCulqi, mock: authenticateMock };

async function post(url: string, body: unknown) {
  const response = await fetch(url, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), credentials: 'same-origin',
  });
  const data = await response.json().catch(() => ({}));
  return { ok: response.ok, status: response.status, data };
}

export function setupCheckout(form: HTMLFormElement, notify: (message: string, kind: 'info' | 'error') => void) {
  const button = form.querySelector<HTMLButtonElement>('button[type="submit"], button:not([type])');
  const busy = (on: boolean) => { if (button) { button.disabled = on; button.style.opacity = on ? '.7' : ''; } };

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!form.reportValidity()) return;
    const data = new FormData(form);
    busy(true);
    notify('Preparando tu pago…', 'info');

    const started = await post('/cuenta/pago/iniciar', {
      courseId: data.get('courseId'), fullName: data.get('fullName'), phone: data.get('phone'),
      country: data.get('country') === '__otro' ? data.get('countryOther') : data.get('country'), notes: data.get('notes'), acceptTerms: data.get('acceptTerms') === 'on',
    }).catch(() => null);

    if (!started || !started.ok) {
      busy(false);
      if (started?.status === 409) { location.href = '/campus'; return; }
      if (started?.status === 401) { location.href = '/ingresar'; return; }
      notify(started?.status === 400 ? 'Revisa los datos del formulario y acepta los términos.' : 'No se pudo iniciar el pago. Inténtalo de nuevo.', 'error');
      return;
    }

    const payment = started.data as StartedPayment;
    const open = openers[payment.provider];
    if (!open) { busy(false); notify('El método de pago no está disponible por ahora.', 'error'); return; }

    let finished = false;
    try {
      await open(payment, {
        onToken: async (token, extra) => {
          notify('Confirmando tu pago…', 'info');
          let result = await post('/cuenta/pago/cobrar', { paymentId: payment.paymentId, token, ...extra }).catch(() => null);
          // El banco exige 3D Secure: se verifica al titular y se reintenta el MISMO cobro con el resultado.
          if (result?.ok && result.data?.status === 'authentication-required') {
            const authenticate = authenticators[payment.provider];
            if (!authenticate) { finished = true; busy(false); notify('Tu tarjeta requiere una verificación que no está disponible. Prueba con otra tarjeta.', 'error'); return; }
            notify('Verificando tu tarjeta con tu banco…', 'info');
            try {
              const authentication3DS = await authenticate(payment, token);
              notify('Confirmando tu pago…', 'info');
              result = await post('/cuenta/pago/cobrar', { paymentId: payment.paymentId, token, ...extra, authentication3DS }).catch(() => null);
            } catch (error) {
              finished = true; busy(false);
              notify((error as Error).message || 'No se pudo verificar tu tarjeta. Prueba con otra tarjeta.', 'error');
              return;
            }
          }
          finished = true;
          if (result?.ok) { location.href = '/campus?estado=pagado'; return; }
          busy(false);
          if (result?.status === 402) notify(String(result.data?.message || 'Tu pago fue rechazado. Prueba con otra tarjeta.'), 'error');
          else notify('No pudimos confirmar tu pago. Si te cobraron, escríbenos por WhatsApp con tu correo y lo resolvemos.', 'error');
        },
        onError: (message) => { finished = true; busy(false); notify(message, 'error'); },
        onClose: () => { if (!finished) { busy(false); notify('', 'info'); } },
      });
    } catch (error) {
      busy(false);
      notify((error as Error).message || 'No se pudo abrir el pago.', 'error');
    }
  });
}
