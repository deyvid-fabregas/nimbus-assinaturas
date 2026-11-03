/**
 * @description Helpers de colecao usados por Selectors, Handlers e Services (todos bulk-safe).
 */
public with sharing class CollectionUtil {
    public static Boolean isNullOrEmpty(Set<Id> values) {
        return values == null || values.isEmpty();
    }

    public static Boolean isNullOrEmpty(Set<String> values) {
        return values == null || values.isEmpty();
    }

    public static Boolean isNullOrEmpty(List<SObject> values) {
        return values == null || values.isEmpty();
    }

    /** Ids nao nulos de um campo de lookup/Id, sem consultar o banco. */
    public static Set<Id> pluckIds(List<SObject> records, Schema.SObjectField field) {
        Set<Id> result = new Set<Id>();
        if (records == null) {
            return result;
        }
        for (SObject record : records) {
            Object value = record.get(field);
            if (value != null) {
                result.add((Id) value);
            }
        }
        return result;
    }

    public static Set<String> pluckStrings(List<SObject> records, Schema.SObjectField field) {
        Set<String> result = new Set<String>();
        if (records == null) {
            return result;
        }
        for (SObject record : records) {
            Object value = record.get(field);
            if (value != null) {
                result.add(String.valueOf(value));
            }
        }
        return result;
    }
}
