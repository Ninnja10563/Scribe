using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Validation;

if (args.Length == 0)
{
    Console.Error.WriteLine("Usage: OOXMLValidation file.docx [file.docx ...]");
    return 2;
}
var failures = 0;
foreach (var path in args)
{
    try
    {
        using var document = WordprocessingDocument.Open(path, false);
        var errors = new OpenXmlValidator(FileFormatVersions.Office2013)
            .Validate(document).ToList();
        foreach (var error in errors)
            Console.Error.WriteLine($"{path}: {error.Part?.Uri} {error.Path?.XPath}: {error.Description}");
        Console.WriteLine($"{path}: {errors.Count} Office 2013 schema/semantic validation errors");
        failures += errors.Count;
    }
    catch (Exception error)
    {
        Console.Error.WriteLine($"{path}: {error.Message}");
        failures++;
    }
}
return failures == 0 ? 0 : 1;
