import { ApiError, request } from '../core/api.js';

const form = document.querySelector('#setup-form');
const message = document.querySelector('#setup-message');
const submit = form.querySelector('[type="submit"]');

function showError(error) {
    if (error instanceof ApiError) {
        if (error.status === 401) {
            return 'O token é inválido, o email não corresponde ao administrador configurado ou a configuração já foi concluída.';
        }
        if (error.status === 409) {
            return 'A conta inicial já foi configurada. Vai à página inicial para iniciar sessão.';
        }
        if (error.status === 400) {
            return 'Confirma os dados. A palavra-passe deve ter entre 12 e 128 caracteres.';
        }
        if (error.status === 429) {
            return 'Foram feitas demasiadas tentativas. Aguarda alguns minutos e tenta novamente.';
        }
        return error.message;
    }
    if (error instanceof TypeError) {
        return 'Não foi possível contactar o servidor. Confirma a ligação e tenta novamente.';
    }
    return 'Ocorreu um erro inesperado. Tenta novamente.';
}

form.addEventListener('submit', async (event) => {
    event.preventDefault();
    message.textContent = '';
    message.classList.remove('is-success');
    submit.disabled = true;
    submit.setAttribute('aria-busy', 'true');

    const values = new FormData(form);
    try {
        await request('/auth/bootstrap', {
            method: 'POST',
            headers: { 'X-Setup-Token': values.get('setupToken') },
            body: JSON.stringify({
                displayName: values.get('displayName'),
                email: values.get('email'),
                password: values.get('password')
            })
        });
        form.reset();
        message.textContent = 'Conta de administrador criada. A configuração inicial já foi concluída; podes iniciar sessão na página inicial.';
        message.classList.add('is-success');
        submit.textContent = 'Configuração concluída';
    } catch (error) {
        message.textContent = showError(error);
        submit.disabled = false;
    } finally {
        submit.setAttribute('aria-busy', 'false');
    }
});
