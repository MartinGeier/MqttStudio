All functions calling async functions should be async.
Always use `await` when calling async functions.
Each page or dialog should have its own viewmodel and does not import other viewmodels or repositories
A dialog or page can have no viewmodel if it is simple and does not require state management.
Always use reactive forms
Define the forms and validators in the viewmodel.
All text should be localized
Localization key must always be prefixed with the pagename or dialog name.
Build methods should not be to long. Split them into smaller build methods if necessary.
Don't insert comments that explain what the prompt requested, such as "method added".
Insert comments only when necessary, such as explaining complex logic or providing context that is not immediately clear from the code itself.
Esc should always cancel the dialog, the Enter key should always submit the dialog.
Dont use nested keys in the json files, use a flat structure instead, unless using pluralization.
Avoid the use of dynamic types, use specific types instead.
Don't use withOpacity, use withValues instead.
Always use {} with if statements, even for single line statements.