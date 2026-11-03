/**
 * @description Utilitarios de texto para validacoes server-side (justificativa, motivo de rejeicao).
 *              Texto formado apenas por espacos (inclusive NBSP e zero-width) e considerado vazio.
 */
public with sharing class TextUtil {
    private static final String INVISIBLE = '[\\s\\u00A0\\u200B\\uFEFF]+';

    public static Boolean isBlank(String value) {
        return value == null || value.replaceAll(INVISIBLE, '').length() == 0;
    }

    /** Tamanho do texto sem espacos nas pontas; zero se for "em branco". */
    public static Integer meaningfulLength(String value) {
        return isBlank(value) ? 0 : value.trim().length();
    }
}
