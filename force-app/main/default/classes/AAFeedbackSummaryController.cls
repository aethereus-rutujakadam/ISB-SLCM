public with sharing class AAFeedbackSummaryController {

    /**
     * Get summarized feedback rollups by Record Type (source)
     * Groups ratings, counts, and averages for a given Academic Associate profile.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getFeedbackSummary(Id aaProfileId, Integer daysFilter) {
        Date startDate = System.today().addDays(-daysFilter);

        List<Feedback__c> feedbacks = [
            SELECT Id, RecordType.DeveloperName, Overall_Rating__c, CreatedDate
            FROM Feedback__c
            WHERE Academic_Associate__c = :aaProfileId
            AND CreatedDate >= :startDate
        ];

        Map<String, Map<String, Object>> summaries = new Map<String, Map<String, Object>>();

        for (Feedback__c fb : feedbacks) {
            String src = fb.RecordType.DeveloperName;

            if (!summaries.containsKey(src)) {
                summaries.put(src, new Map<String, Object>{
                    'source' => src,
                    'ratings' => new List<Integer>(),
                    'count' => 0,
                    'avgRating' => 0
                });
            }

            Map<String, Object> data = summaries.get(src);
            data.put('count', (Integer)data.get('count') + 1);

            // Convert picklist rating (1–5) to Integer
            if (fb.Overall_Rating__c != null) {
                try {
                    Integer rating = Integer.valueOf(fb.Overall_Rating__c);
                    ((List<Integer>)data.get('ratings')).add(rating);
                } catch (Exception e) {
                    // Skip invalid or non-numeric ratings
                }
            }
        }

        // Calculate average per source
        for (String key : summaries.keySet()) {
            Map<String, Object> data = summaries.get(key);
            List<Integer> ratings = (List<Integer>)data.get('ratings');

            if (!ratings.isEmpty()) {
                Decimal avg = 0;
                for (Integer r : ratings) {
                    avg += r;
                }
                avg = avg / ratings.size();
                data.put('avgRating', avg.setScale(2));
            }
            data.remove('ratings');
        }

        return new List<Map<String, Object>>(summaries.values());
    }

    /**
     * Get detailed feedback records for a specific source (RecordType)
     * Used when clicking “View More” in the LWC
     */
    @AuraEnabled(cacheable=true)
    public static List<FeedbackDetailWrapper> getFeedbackDetails(Id aaProfileId, String recordTypeDeveloperName) {
        List<Feedback__c> records = [
            SELECT Id, Name, Overall_Rating__c, Comments__c, CreatedDate, CreatedBy.Name
            FROM Feedback__c
            WHERE Academic_Associate__c = :aaProfileId
            AND RecordType.DeveloperName = :recordTypeDeveloperName
            ORDER BY CreatedDate DESC
        ];

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        List<FeedbackDetailWrapper> wrapperList = new List<FeedbackDetailWrapper>();

        for (Feedback__c rec : records) {
            FeedbackDetailWrapper wrap = new FeedbackDetailWrapper();
            wrap.Id = rec.Id;
            wrap.Name = rec.Name;
            wrap.OverallRating = rec.Overall_Rating__c;
            wrap.Comments = rec.Comments__c;
            wrap.RecordUrl = baseUrl + '/lightning/r/Feedback__c/' + rec.Id + '/view';
            wrapperList.add(wrap);
        }

        return wrapperList;
    }

    /**
     * Wrapper class for detailed feedback records
     * Includes a generated RecordUrl for clickable links in LWC
     */
    public class FeedbackDetailWrapper {
        @AuraEnabled public Id Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String OverallRating;
        @AuraEnabled public String Comments;
        @AuraEnabled public String RecordUrl;
    }
}