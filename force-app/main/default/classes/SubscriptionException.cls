/**
 * @description Excecao de negocio do modulo. A mensagem e SEMPRE amigavel e acionavel
 *              (pode ser exibida ao usuario). O codigo e estavel e serve para logica/testes.
 *              Falhas inesperadas (nao SubscriptionException) devem ir para TechnicalLogger.
 */
public class SubscriptionException extends Exception {
    public String code { get; private set; }

    public SubscriptionException(String code, String message) {
        this(message);
        this.code = code;
    }
}
