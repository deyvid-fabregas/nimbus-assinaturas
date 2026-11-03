/**
 * @description Selector de Pricebook2 / PricebookEntry (WITH USER_MODE).
 *              LIMITACAO CONHECIDA: em orgs com multi-moeda, PricebookEntry existe uma vez por moeda e
 *              seria preciso filtrar por CurrencyIsoCode (campo inexistente em orgs single-currency, por
 *              isso nao referenciado aqui). Registrado em DECISOES_E_LIMITACOES.md.
 */
public with sharing class PricebookSelector {

    public List<Pricebook2> selectActiveByName(String pricebookName) {
        if (String.isBlank(pricebookName)) {
            return new List<Pricebook2>();
        }
        return [
            SELECT Id, Name, IsActive, IsStandard
            FROM Pricebook2
            WHERE Name = :pricebookName AND IsActive = true
            WITH USER_MODE
            LIMIT 1
        ];
    }

    public List<Pricebook2> selectByIds(Set<Id> pricebookIds) {
        if (CollectionUtil.isNullOrEmpty(pricebookIds)) {
            return new List<Pricebook2>();
        }
        return [
            SELECT Id, Name, IsActive, IsStandard
            FROM Pricebook2
            WHERE Id IN :pricebookIds
            WITH USER_MODE
        ];
    }

    /** Entradas de preco ATIVAS do pricebook para os produtos informados (1 consulta para o lote). */
    public List<PricebookEntry> selectActiveEntries(Id pricebookId, Set<Id> productIds) {
        if (pricebookId == null || CollectionUtil.isNullOrEmpty(productIds)) {
            return new List<PricebookEntry>();
        }
        return [
            SELECT Id, Pricebook2Id, Product2Id, UnitPrice, IsActive
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId AND Product2Id IN :productIds AND IsActive = true
            WITH USER_MODE
        ];
    }

    /**
     * Entradas ATIVAS para varios pricebooks e produtos em UMA consulta (sem SOQL em loop quando o lote
     * mistura contratos com pricebooks diferentes). O chamador separa o resultado por Pricebook2Id.
     */
    public List<PricebookEntry> selectActiveEntriesForPricebooks(Set<Id> pricebookIds, Set<Id> productIds) {
        if (CollectionUtil.isNullOrEmpty(pricebookIds) || CollectionUtil.isNullOrEmpty(productIds)) {
            return new List<PricebookEntry>();
        }
        return [
            SELECT Id, Pricebook2Id, Product2Id, UnitPrice, IsActive
            FROM PricebookEntry
            WHERE Pricebook2Id IN :pricebookIds AND Product2Id IN :productIds AND IsActive = true
            WITH USER_MODE
        ];
    }
}
