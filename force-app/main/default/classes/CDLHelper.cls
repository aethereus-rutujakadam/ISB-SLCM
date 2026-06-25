public without sharing class CDLHelper {
    public class Request{
        @InvocableVariable(required=true)
        public Id contentDocumentId;
        
        @InvocableVariable(required=true)
        public Id linkedEntityId;
    }
    
    @InvocableMethod(label='Create ContentDocumentLink' description='create')
    
    public static void createCDL(List<Request> requests){
        if(requests == null || requests.isEmpty()) return;
        
        List<ContentDocumentLink> cdls = new List<ContentDocumentLink>();
        for(Request r : requests){
            if(r == null || r.ContentDocumentId == null || r.linkedEntityId == null)continue ;
            ContentDocumentLink cdl =new ContentDocumentLink(ContentDocumentId = r.ContentDocumentId, 
                                                            linkedEntityId = r.linkedEntityId,
                                                            ShareType = 'V',
                                                            Visibility = 'AllUsers');
            cdls.add(cdl) ;          
        }
        if(!cdls.isEmpty()){
            try{
                insert cdls; 
            }  catch(DmlException e){
                System.debug('CDL insert failed:'+e.getMessage());
                throw e;
            }
          
        }
    }
}