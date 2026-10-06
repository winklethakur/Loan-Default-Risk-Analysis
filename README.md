# Loan Default Risk Dashboard

This is a credit risk project built on the Lending Club loan data from Kaggle. I wanted to answer two questions a credit team would care about. Which kinds of borrowers default the most? And which applications should a person check by hand before a loan is approved?

I used MySQL to clean and analyse the data and to build a risk score, and Power BI to put it all into a four page dashboard.

![Overview page](Images/01_overview.png)

## The question

Which customer segments have the highest loan default probability, and which applications should the credit team manually review?

## The data

The data is the Lending Club accepted loans file from Kaggle, covering 2007 to 2018: https://www.kaggle.com/datasets/wordsforthewise/lending-club

I kept only loans that had a final result, meaning they ended as Fully Paid, Charged Off or Default. That left 1,345,350 loans. After one more filter, explained further down, I worked with 673,553 loans issued between 2007 and 2015. Of those, 99,785 defaulted, which is 14.81%. I use that number as the average everywhere in this project.

When I say a loan defaulted, I mean it ended as Charged Off or Default. Charged Off means the lender gave up on getting the money back.

## What I found

Here is the safest and the riskiest group for each factor. The average is 14.81%.

| Factor | Safest group | Riskiest group |
|---|---|---|
| FICO score | 750 or above: 6.05% | Under 680: 19.07% |
| Loan purpose | Car: 11.84% | Small business: 24.40% |
| Loan term | 36 months: 13.90% | 60 months: 25.16% |
| Annual income | 150k or more: 10.27% | Under 30k: 20.70% |
| Debt to income (DTI) | Under 10: 11.46% | 30 to 39: 20.61% |
| Employment length | 10 or more years: 13.71% | Not provided: 20.84% |
| State | DC: 9.95% | MS: 18.68% |

FICO score separated borrowers best. People under 680 defaulted 19.1% of the time and people at 750 or above only 6.1%.

Income behaves the way you would expect. The default rate drops at every step, from 20.7% for people earning under 30k to 10.3% for people earning 150k or more.

Loans with a 60 month term default far more often than 36 month loans, 25.2% against 13.9%. I was worried this was only because the 60 month loans come from older years that happened to be riskier. So I compared both terms inside the same issue year for 2010 to 2013. The gap stayed between 11 and 14 points every time, so it holds up.

Employment length surprised me. For people who gave it, the default rate stays between 13.7% and 15.2% no matter how long they had worked. The only group that stands out is the one where employment length was missing, at 20.8%.

Small business loans have the highest default rate of any purpose, but they are only 1.3% of all loans. Debt consolidation is 57% of loans and sits at 15.6%. So the riskiest segment is not always the one that produces the most defaults. That is why the dashboard shows the number of loans next to every rate.

I also looked at state. It runs from about 10% in DC to 18.7% in Mississippi. It is on the dashboard, but I left it out of the risk score on purpose, because location can act as a stand in for protected groups.

## The risk score

I built a simple points scorecard, not a machine learning model. This is an analyst project, and I wanted every point to be something I could explain.

Each loan gets points from six things: loan term, purpose, income, employment length, FICO score and debt to income. A group earns points based on how far its default rate sits above or below the average. A risky group gets positive points and a safe group gets negative ones. A loan's score is the total, and in this data it runs from minus 24 to 33.

Then I sorted loans into five tiers by score and checked how many loans in each tier really defaulted:

| Tier | Score | Share of loans | Default rate |
|---|---|---|---|
| 1 Very Low | minus 11 or lower | 10.3% | 5.30% |
| 2 Low | minus 10 to minus 1 | 38.7% | 10.86% |
| 3 Medium | 0 to 4 | 26.5% | 16.16% |
| 4 High | 5 to 9 | 16.5% | 21.17% |
| 5 Very High | 10 or higher | 8.0% | 28.63% |

The factors overlap. Low income and a low FICO score often come together, so adding their points can count the same risk twice. Because of that I did not treat the points as probabilities. The default rate shown for each tier is what actually happened to the loans in it.

To make sure the score was not just memorising the past, I worked out the points using loans from 2007 to 2013 and then tested the score on loans from 2014 and 2015. The default rate went up with the score in both periods. Loans scoring 5 to 9, for example, defaulted 20.8% of the time in the training years and 21.4% in the test years.

## Which applications to review

Where to draw the line depends on how many applications the team can check, so the dashboard has a slider for it. This table shows what each choice covers. Each row assumes the team reviews that tier and every riskier one.

| Review | Share of applications | Share of all defaults caught |
|---|---|---|
| Tier 5 | 8.0% | 15.5% |
| Tiers 4 and 5 | 24.5% | 39.0% |
| Tiers 3 to 5 | 51.0% | 67.9% |
| Tiers 2 to 5 | 89.7% | 96.3% |

I want to be clear about what the score can and cannot do. Even in the riskiest tier, about 71% of borrowers paid their loan back. The 18 highest scoring applications (a score of 30 or more) still repaid two times out of three. The score tells a team where to look first. It should not be used to reject people.

## The dashboard

The Power BI report has four pages.

1. **Overview.** Total loans, defaults and the default rate, then loans issued and default rate by year, and default rate by risk tier.
2. **Borrower Profile.** Default rate by income, FICO score, debt to income and employment length.
3. **Loan Type and Location.** Default rate by loan purpose, loan term and state.
4. **Review Queue.** A slider for the lowest risk score to review, how many applications and defaults that covers, and a list of the highest risk applications.

![Borrower profile](Images/02_borrower_profile.png)
![Loan type and location](Images/03_loan_type_location.png)
![Review queue](Images/04_review_queue.png)

There is also a PDF copy of the report in the powerbi folder.

## One decision that changed my results

When I first looked at default rate by year, 2016 and 2017 showed about 23%, which looked wrong next to 13% to 16% for the earlier years. The cause was something I had done myself. I had removed loans that were still running, because they have no final result yet. But that quietly changes the numbers.

Here is the idea with 10 loans issued in 2016. Six are still running and being paid normally, two were paid off early, and two were charged off. The real failure rate is 2 out of 10, which is 20%. If I throw away the six running loans, I am left with 4 loans and 2 of them failed, which looks like 50%. The healthy loans disappeared, so the failures look much bigger than they are.

The fix was to keep only loans whose full term had already ended before the data was collected at the end of 2018. Then every loan in the sample has had the same time to succeed or fail. For loans issued in 2015 the default rate fell from 20.2% to 14.9% after this fix, and for 2014 from 18.5% to 13.7%.

It costs me about half of the loans, and after 2013 only 36 month loans are left. I decided a smaller but fair sample was better than a bigger one with a built in bias.

I also kept two kinds of columns out on purpose. I never loaded anything that is only known after a loan starts, such as payments received. And I kept grade and interest rate out of the score. Those are Lending Club's own risk ratings, so using them would be circular.

## Limitations

* The data is from the US between 2007 and 2018. The method would carry over to another lender, but the numbers would not. In India a score like this would use credit bureau data such as CIBIL.
* The score separates borrowers reasonably well but not perfectly. I did not calculate AUC or KS, which a full validation would include.
* There are no 60 month loans in the test years, so I could not test the term factor on unseen loans. Scores of 20 and above are only checked on older data.
* Risk moves over time. At the same score, the test loans defaulted up to about 1.3 points more than the training loans. A real scorecard would need to be recalibrated regularly.
* I did not run a fairness check. Leaving out state helps, but other factors such as income can still be linked to protected groups.
* The review queue uses old loans whose results are already known, so it is a demonstration. A real queue would score new applications.

If I carried on with this, I would compare the scorecard with a logistic regression, try weight of evidence instead of simple point differences, and measure how much the tiers drift year by year.

## Files

```
Images/
Power BI/loan_default_risk_dashboard.pbix
Power BI/loan_default_risk_dashboard.pdf
SQL/loan_default_risk.sql
README.md
```

The Kaggle file is too large to include, so download it from the link above.

## How to run it

1. Download accepted_2007_to_2018Q4.csv from Kaggle.
2. Prepare loans_filtered.csv. Keep only the rows where loan_status is Fully Paid, Charged Off or Default, and only the 24 columns listed in the LOAD DATA statement of the SQL file, in that same order (it is the order they appear in the Kaggle file). The raw file is large, so use a tool that can read it in chunks.
3. In MySQL, run sql/loan_default_risk.sql one section at a time. Change the file path in the LOAD DATA statement, and turn on local_infile on both the server and the client. The script expects Windows line endings. On Mac or Linux, change them to `\n`.
4. Open Power BI Desktop, connect to the loan_risk database and load loans_dashboard, tier_summary and score_points.

Or skip all of that and open the PDF.

## Tools

MySQL and Power BI Desktop (DAX measures and a what if parameter).

## Author

Built by Winkle. [GitHub](https://github.com/winklethakur) and [LinkedIn](https://www.linkedin.com/in/winkle-data-scientist)
