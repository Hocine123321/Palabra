# Study → Exam

Tests the person on their own vocabulary. Spec for what exists; see AGENTS.md for the rules to keep.

## What the person sees

1. **Study tab → Exam tile** → setup: which words (all, weakest first, recently added, Need Review, a section, a tag), how many questions (5/10/20/30), which skills, and an "Use AI" switch.
2. **Questions**, one at a time, with instant feedback and a Next button. "End Exam" keeps what was answered so far.
3. **Result**: score ring, score per skill, the missed answers, AI coach (when AI is on), "Practise the Missed Words" (a new exam on just those words), "Add Them to Need Review".
4. **Past Exams**: every saved exam (newest 100) and a "Needs practice" list of words that keep going wrong.

## Skills and question kinds

| Skill | Kinds | Needs |
|---|---|---|
| Meaning | pick the meaning, pick the Spanish word, pick the similar word, match pairs | library only |
| Typing | type the Spanish, type the meaning | library only |
| Grammar | fill the blank (cloze), choose the right form, put the words in order | words with examples/forms |
| Listening | hear a word or short sentence, type it | phone's own voice (free) |
| Speaking | say the word, the phone listens | speech recognition + microphone permission |
| Writing | write a sentence with the word, translate a sentence | AI (or self-check when AI can't answer) |

## Grading

`AnswerMatcher`: exact = 1, missing accents = 0.75, one/two letters off = 0.5 (none for words under 4 letters, one under 9), otherwise 0. English answers ignore "to/the/a" and bracketed notes and accept any listed meaning. Matching: 1 minus a share per mistake. Ordering: share of words in place. AI-graded writing: 0...1 with feedback and a corrected sentence.

## AI (optional)

`ExamAI` (generic `generateJSON`): fresh cloze + translation sentences for the exam's words (one request, at most 15 words), grading a written answer, and the coach summary. Failures never block the exam: the exam is built from the person's own words and a notice says so; an unchecked written answer is graded by the person.

## Data

`ExamResult` (SwiftData): config JSON, answer records JSON, score sum, duration. In the `.palabra` backup as `exams`.
