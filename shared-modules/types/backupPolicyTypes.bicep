@description('The schedule policy for an Azure IaaS virtual machine backup policy.')
@export()
type iaasSchedulePolicyType = {
  @description('The type of schedule policy.')
  schedulePolicyType: schedulePolicyType | 'SimpleSchedulePolicyV2'
  @description('The frequency at which backups run.')
  scheduleRunFrequency: scheduleRuleFrequency | 'Weekly'

  @description('The hourly backup schedule configuration.')
  hourlySchedule: hourlySchedule?
  @description('The daily backup schedule configuration.')
  dailySchedule: dailySchedule?
  @description('The weekly backup schedule configuration.')
  weeklySchedule: weeklySchedule?

  @description('The days on which the backup schedule runs.')
  scheduleRunDays: scheduleRunDays?
  @description('The times at which the backup schedule runs.')
  scheduleRunTimes: string[]?

  @description('The interval, in weeks, at which the weekly schedule runs.')
  scheduleWeeklyFrequency: int?
}

@description('The schedule policy for an Azure File share backup policy.')
@export()
type fileShareSchedulePolicyType = {
  @description('The type of schedule policy.')
  schedulePolicyType: schedulePolicyType
  @description('The frequency at which backups run.')
  scheduleRunFrequency: scheduleRuleFrequency

  @description('The hourly backup schedule configuration.')
  hourlySchedule: hourlySchedule?
  @description('The daily backup schedule configuration.')
  dailySchedule: dailySchedule?

  @description('The days on which the backup schedule runs.')
  scheduleRunDays: scheduleRunDays?
  @description('The times at which the backup schedule runs.')
  scheduleRunTimes: string[]?
}

@description('The long-term retention policy for protected backup items.')
@export()
type retentionPolicyType = {
  @description('The type of retention policy.')
  retentionPolicyType: 'LongTermRetentionPolicy'

  @description('The daily retention schedule.')
  dailySchedule: {
    @description('The times at which daily recovery points are retained.')
    retentionTimes: string[]
    @description('The duration for which daily recovery points are retained.')
    retentionDuration: {
      @description('The number of days for which recovery points are retained.')
      count: int
      @description('The unit of the daily retention duration.')
      durationType: 'Days'
    }
  }

  @description('The weekly retention schedule.')
  weeklySchedule: {
    @description('The days of the week on which recovery points are retained.')
    daysOfTheWeek: scheduleRunDays
    @description('The times at which weekly recovery points are retained.')
    retentionTimes: string[]
    @description('The duration for which weekly recovery points are retained.')
    retentionDuration: {
      @description('The number of weeks for which recovery points are retained.')
      count: int
      @description('The unit of the weekly retention duration.')
      durationType: 'Weeks'
    }
  }?

  @description('The monthly retention schedule.')
  monthlySchedule: {
    @description('The format used to select monthly recovery points.')
    retentionScheduleFormatType: 'Daily' | 'Weekly'
    @description('The day-of-month selection for monthly retention.')
    retentionScheduleDaily: {
      @description('The days of the month on which recovery points are retained.')
      daysOfTheMonth: [
        {
          @description('The calendar date on which the recovery point is retained.')
          date: int
          @description('Whether the selected date represents the last day of the month.')
          isLast: bool
        }
      ]
    }?
    @description('The week-and-day selection for monthly retention.')
    retentionScheduleWeekly: {
      @description('The days of the week on which recovery points are retained.')
      daysOfTheWeek: scheduleRunDays
      @description('The weeks of the month in which recovery points are retained.')
      weeksOfTheMonth: ('First')[]
    }?

    @description('The times at which monthly recovery points are retained.')
    retentionTimes: string[]
    @description('The duration for which monthly recovery points are retained.')
    retentionDuration: {
      @description('The number of months for which recovery points are retained.')
      count: int
      @description('The unit of the monthly retention duration.')
      durationType: 'Months'
    }
  }?

  @description('The yearly retention schedule.')
  yearlySchedule: {
    @description('The duration for which yearly recovery points are retained.')
    retentionDuration: {
      @description('The number of years for which recovery points are retained.')
      count: int
      @description('The unit of the yearly retention duration.')
      durationType: 'Years'
    }
    @description('The times at which yearly recovery points are retained.')
    retentionTimes: string[]
    @description('The format used to select yearly recovery points.')
    retentionScheduleFormatType: 'Weekly'
    @description('The months in which yearly recovery points are retained.')
    monthsOfYear: (
      | 'January'
      | 'February'
      | 'March'
      | 'April'
      | 'May'
      | 'June'
      | 'July'
      | 'August'
      | 'September'
      | 'October'
      | 'November'
      | 'December')[]
    @description('The week-and-day selection for yearly retention.')
    retentionScheduleWeekly: {
      @description('The days of the week on which recovery points are retained.')
      daysOfTheWeek: scheduleRunDays
      @description('The weeks of the month in which recovery points are retained.')
      weeksOfTheMonth: ('First')[]
    }?
    @description('The day-of-month selection for yearly retention.')
    retentionScheduleDaily: {
      @description('The days of the month on which recovery points are retained.')
      daysOfTheMonth: [
        {
          @description('The calendar date on which the recovery point is retained.')
          date: int
          @description('Whether the selected date represents the last day of the month.')
          isLast: bool
        }
      ]
    }?
  }?
}

@description('The configuration for an hourly backup schedule.')
type hourlySchedule = {
  @description('The interval, in hours, between backup runs.')
  interval: int
  @description('The duration, in hours, of the scheduling window.')
  scheduleWindowDuration: int
  @description('The start time of the scheduling window.')
  scheduleWindowStartTime: string
}

@description('The configuration for a daily backup schedule.')
type dailySchedule = {
  @description('The times at which the daily backup schedule runs.')
  scheduleRunTimes: string[]
}

@description('The configuration for a weekly backup schedule.')
type weeklySchedule = {
  @description('The days on which the weekly backup schedule runs.')
  scheduleRunDays: scheduleRunDays
  @description('The times at which the weekly backup schedule runs.')
  scheduleRunTimes: string[]
}

@description('The days of the week on which a schedule runs.')
type scheduleRunDays = ('Sunday' | 'Monday' | 'Tuesday' | 'Wednesday' | 'Thursday' | 'Friday' | 'Saturday')[]
@description('The frequency at which a schedule rule runs.')
type scheduleRuleFrequency = 'Hourly' | 'Daily'
@description('The type of simple schedule policy.')
type schedulePolicyType = 'SimpleSchedulePolicy'
