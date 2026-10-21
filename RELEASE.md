# Release (Developer ID + notarização)

Distribuição fora da Mac App Store, com Hardened Runtime e sem App Sandbox.

1. Guarde as credenciais de notarização no Keychain (uma vez):
   ```sh
   xcrun notarytool store-credentials "cleaner-notary" \
     --apple-id "seu@email" --team-id "ABCDE12345" --password "<senha de app>"
   ```
2. Exporte as variáveis (nunca versione):
   ```sh
   export DEVELOPER_ID_APP="Developer ID Application: Seu Nome (ABCDE12345)"
   export TEAM_ID="ABCDE12345"
   export NOTARY_PROFILE="cleaner-notary"
   ```
3. Valide sem assinar: `scripts/release.sh --dry-run`
4. Rode: `scripts/release.sh` → gera `.build/release/Cleaner.zip` assinado, notarizado e grampeado.

O script verifica com `codesign`, `spctl` e `stapler validate` no final.
