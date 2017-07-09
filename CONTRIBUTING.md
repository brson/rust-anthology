Some notes on Anthology maintenance.

Presently, contributions that fix existing content are welcome.
Contributions that add chapters are not, as the selection process is
under reevalution.

## Evaluating a blog post

- Is there useful content? In particular, is there content that is not
  already represented better in existing chapters?
- Is the text well written? Brilliant prose is a no-brainer. We want
  it. Average prose is also no reason to exclude a chapter, though for
  practical reasons we need to keep the editing required to a
  minimum. Poorer prose demands exceptional content.
- Is the content substantial? A short text may not be a good
  candidate, though short chapters with exceptional content that is
  not well-represented elsewhere may still be good candidates.
- Is the content likely to be obsoleted easily? Probably not a good
  candidate.
- Is the content too domain specific? Probably not a good candidate.
- Does the content fit into some 'theme' with other content? Look for
  places where we can group chapters into book sections.
- Is the content still relevant and idiomatic?

## Adding a blog post

Importing a chapter to the book includes these steps:

- Acquire the original source and convert it to markdown. This may
  mean contacting the author if the source is not obviously
  available. In these cases you should not assume they want their text
  redistributed, so explain your purpose clearly.
- Create a markdown file in `src/` with a name reflecting the title.
- If the source is spread across multiple blog posts, consolidate them
  into one, with each given their own section heading, "Part N:
  $subtitle".
- Add a metadata footer, following existing convention. This does not
  need to be complete yet, but if you have the original URL and the
  licensing information, you may as well include it now.
- Add the chapter in an appropriate place to `SUMMARY.md`.
- Add the chapter to `into.md` with a one-paragraph description. If
  the author does not have an entry in `authors.md` yet, you do not
  need to add it now.
- Run `mdbook test`. For any tests that fail either fix them or ignore
  them. We will revisit later.
