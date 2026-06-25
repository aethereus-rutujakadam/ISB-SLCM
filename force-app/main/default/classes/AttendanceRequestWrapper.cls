public class AttendanceRequestWrapper  {
  @JsonProperty('CourseOfferingId')
    public String CourseOfferingId;

    @JsonProperty('Section')
    public String Section;

    @JsonProperty('SessionDate')
    public String SessionDate;     // SAFE replacement for "Date"

    @JsonProperty('SessionTime')
    public String SessionTime;     // SAFE replacement for "Time"

    @JsonProperty('Students')
    public List<StudentData> Students;

    public class StudentData {
        @JsonProperty('StudentPGID')
        public String StudentPGID;

        @JsonProperty('Status')
        public String Status;
    }
}