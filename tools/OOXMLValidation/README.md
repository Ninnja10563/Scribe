# Independent DOCX validation

This development-only command checks exported packages with Microsoft's Open XML SDK 3.5.1, targeting Office 2013 (including resolved-comment extensions). It is not linked to or shipped inside Scribe.

```sh
dotnet restore tools/OOXMLValidation --locked-mode
dotnet run --project tools/OOXMLValidation --no-restore -- path/to/Smoke.docx
```

CI validates the DOCX emitted by the optimized native application. Release publication depends on this check as well as macOS tests and launch/render checks. Schema validation does not establish visual fidelity or replace manual interoperability testing in Word.

Reference: [Microsoft's document validation guide](https://learn.microsoft.com/en-us/office/open-xml/word/how-to-validate-a-word-processing-document).
