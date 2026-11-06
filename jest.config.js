const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    testMatch: ['<rootDir>/test/lwc/**/*.test.js'],
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver'],
    collectCoverageFrom: ['force-app/main/default/lwc/**/*.js', '!**/__tests__/**', '!**/__mocks__/**'],
    coverageThreshold: {
        global: { statements: 80 }
    }
};
