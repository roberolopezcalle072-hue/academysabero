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
  handlers: { onToken: (token: string) => Promise<void>; onError: (message: string) => void; onClose: () => void },
) => Promise<void>;

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
  Culqi.publicKey = String(payment.config.publicKey ?? '');
  Culqi.settings({ title: 'SABERO Academy', currency: payment.currency, description: payment.title, amount: payment.amountMinor });
  Culqi.options({
    lang: 'es', installments: false, modal: true,
    paymentMethods: { tarjeta: true, yape: true, billetera: false, bancaMovil: false, agente: false, cuotealo: false },
  });
  w.culqi = async () => {
    if (Culqi.token) {
      Culqi.close();
      await onToken(String(Culqi.token.id));
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
    await onToken('tok_mock_ok');
  } else {
    await onToken('tok_mock_bad');
  }
  onClose();
};

const openers: Record<string, Opener> = { culqi: openCulqi, mock: openMock };

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
        onToken: async (token) => {
          notify('Confirmando tu pago…', 'info');
          const result = await post('/cuenta/pago/cobrar', { paymentId: payment.paymentId, token }).catch(() => null);
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
